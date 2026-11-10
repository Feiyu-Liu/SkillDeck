import 'dart:async';

import 'package:skills_manager/features/skills/data/repositories/skills_workspace_repository.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';

import 'read_fixtures.dart';

/// Strict fake: only the write seam is available, and every mutation is counted.
final class WriteRepository implements SkillsWorkspaceRepository {
  WriteRepository()
    : current = testSnapshot(
        skills: [
          for (final slot in ['alpha', 'beta', 'gamma'])
            testSkill(
              id: slot,
              slot: slot,
              name: slot,
              favorite: false,
              tags: [],
              activations: [],
            ),
        ],
      );
  @override
  SkillsWorkspaceSnapshot current;
  final calls = <String>[];
  final skillSets = <Set<WorkspaceSkillId>>[];
  final reviewedRevisions = <int>[];
  final locations = <Set<String>?>[];
  final failures = <int, WorkspaceErrorCode>{};
  final pending = <int>{};
  bool occupied = false;
  int? blockAt;
  final started = Completer<void>();
  bool taskCancelled = false;
  int active = 0;
  int maximumActive = 0;

  WorkspaceTask<T> task<T>(String name, T Function() value) {
    calls.add(name);
    final index = calls.length;
    final completion = Completer<WorkspaceCompletion<T>>();
    active++;
    if (active > maximumActive) maximumActive = active;
    void finish(WorkspaceCompletion<T> result) {
      if (!completion.isCompleted) {
        active--;
        completion.complete(result);
      }
    }

    if (blockAt == index) {
      if (!started.isCompleted) started.complete();
    } else if (failures[index] case final code?) {
      finish(
        WorkspaceFailed(
          failure: WorkspaceFailure(
            code: code,
            operation: WorkspaceOperationKind.activate,
            diagnostic: 'sensitive text',
            context: {'path': '/private/never-print'},
          ),
        ),
      );
    } else if (pending.contains(index)) {
      finish(
        WorkspaceCommittedPending(
          operationId: 'pending-$index',
          committedRevision: 8,
        ),
      );
    } else {
      finish(WorkspaceCompleted(value: value()));
    }
    return WorkspaceTask(
      current: WorkspaceOperationProgress(
        operationId: 'op-$index',
        kind: WorkspaceOperationKind.activate,
        phase: WorkspaceOperationPhase.queued,
      ),
      // A fresh cancellation future keeps deterministic-clock tests in their
      // own zone (Stream.empty caches a root-zone cancellation future).
      states: StreamController<WorkspaceOperationProgress>(
        onCancel: () async {},
      ).stream,
      completed: completion.future,
      cancel: () async {
        taskCancelled = true;
        finish(
          WorkspaceFailed(
            failure: WorkspaceFailure(
              code: WorkspaceErrorCode.operationCancelled,
              operation: WorkspaceOperationKind.activate,
            ),
          ),
        );
      },
    );
  }

  void publish({
    List<SkillProjectRoot>? roots,
    List<WorkspacePersonalTag>? tags,
  }) {
    current = SkillsWorkspaceSnapshot(
      revision: current.revision + 1,
      skills: current.skills,
      projectRoots: roots ?? current.projectRoots,
      personalTags: tags ?? current.personalTags,
    );
  }

  WorkspaceMutationReceipt receipt() =>
      WorkspaceMutationReceipt(snapshot: current);
  @override
  WorkspaceTask<WorkspaceActivationAttempt> activate({
    required Set<WorkspaceSkillId> skillIds,
    required WorkspaceScope scope,
    required Set<String> agentIds,
    String? projectRootId,
    WorkspaceActivationMethod activationMethod =
        WorkspaceActivationMethod.automatic,
  }) {
    skillSets.add(skillIds);
    return task(
      'activate',
      () => occupied
          ? WorkspaceActivationTakeoverRequired(_Draft())
          : WorkspaceActivationCompleted(receipt()),
    );
  }

  @override
  WorkspaceTask<WorkspaceMutationReceipt> deactivate({
    required Set<WorkspaceSkillId> skillIds,
    Set<String>? locations,
  }) {
    skillSets.add(skillIds);
    this.locations.add(locations);
    return task('deactivate', receipt);
  }

  @override
  WorkspaceTask<WorkspaceMutationReceipt> remove({
    required Set<WorkspaceSkillId> skillIds,
    required int expectedRevision,
  }) {
    skillSets.add(skillIds);
    reviewedRevisions.add(expectedRevision);
    return task('remove', receipt);
  }

  final replaceSourceRequests =
      <
        ({
          WorkspaceSkillId skillId,
          SkillSourceInput source,
          int expectedRevision,
        })
      >[];
  void Function()? onReplacementCommit;

  @override
  WorkspaceTask<WorkspaceMutationReceipt> replaceSource({
    required WorkspaceSkillId skillId,
    required SkillSourceInput source,
    required int expectedRevision,
  }) {
    replaceSourceRequests.add((
      skillId: skillId,
      source: source,
      expectedRevision: expectedRevision,
    ));
    if (current.revision != expectedRevision) {
      failures[calls.length + 1] = WorkspaceErrorCode.staleSnapshot;
    }
    if (pending.contains(calls.length + 1)) publish();
    return task('source replace', () {
      publish();
      final committed = receipt();
      onReplacementCommit?.call();
      return committed;
    });
  }

  @override
  WorkspaceTask<SkillsWorkspaceSnapshot> deletePersonalTag(String tagId) =>
      task('tag delete $tagId', () => current);

  @override
  WorkspaceTask<WorkspaceMutationReceipt> registerProjectRoot({
    required String path,
    String? id,
  }) => task('register', () {
    publish(
      roots: [
        ...current.projectRoots,
        SkillProjectRoot(id: id ?? 'new-root', path: path),
      ],
    );
    return receipt();
  });
  @override
  WorkspaceTask<SkillsWorkspaceSnapshot> setFavorite({
    required WorkspaceSkillId skillId,
    required bool isFavorite,
  }) => task('favorite', () => current);
  @override
  WorkspaceTask<SkillsWorkspaceSnapshot> saveNote({
    required WorkspaceSkillId skillId,
    required String note,
  }) => task('note set', () => current);
  @override
  WorkspaceTask<SkillsWorkspaceSnapshot> deleteNote(WorkspaceSkillId skillId) =>
      task('note clear', () => current);
  @override
  WorkspaceTask<WorkspacePersonalTag> createPersonalTag({
    required String name,
    String? color,
  }) => task('tag create', () {
    final tag = WorkspacePersonalTag(
      id: 'created-${calls.length}',
      name: name,
      color: color,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );
    publish(tags: [...current.personalTags, tag]);
    return tag;
  });
  @override
  WorkspaceTask<WorkspacePersonalTag> updatePersonalTag({
    required String tagId,
    required String name,
    String? color,
  }) => task(
    'tag rename',
    () => WorkspacePersonalTag(
      id: tagId,
      name: name,
      color: color,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    ),
  );
  @override
  WorkspaceTask<SkillsWorkspaceSnapshot> assignPersonalTag({
    required WorkspaceSkillId skillId,
    required String tagId,
  }) => task('tag assign', () => current);
  @override
  WorkspaceTask<SkillsWorkspaceSnapshot> unassignPersonalTag({
    required WorkspaceSkillId skillId,
    required String tagId,
  }) => task('tag unassign', () => current);
  @override
  Stream<SkillsWorkspaceSnapshot> get snapshots => publications.stream;
  final publications = StreamController<SkillsWorkspaceSnapshot>.broadcast(
    sync: true,
  );
  @override
  Future<WorkspaceCompletion<SkillsWorkspaceSnapshot>> open() async =>
      WorkspaceCompleted(value: current);

  final inspectedSources = <SkillSourceInput>[];
  final installRequests = <WorkspaceInstallRequest>[];
  List<WorkspaceSourceCandidate> candidates = [candidate('delta')];
  WorkspaceErrorCode? inspectionFailure;
  Map<String, Object?> inspectionFailureContext = const {};
  bool conflictAfterUpdate = false;
  void Function()? onPublish;
  List<WorkspaceUpdateReport> updateReports = [];

  static WorkspaceSourceCandidate candidate(
    String slot, {
    String? name,
    String? skillPath,
  }) => WorkspaceSourceCandidate(
    declaredName: name ?? slot,
    description: 'Description of $slot',
    slotKey: slot,
    skillPath: skillPath ?? slot,
    contentHash: 'hash-$slot',
    fileCount: 1,
    byteSize: 100,
  );

  @override
  WorkspaceTask<WorkspaceSourceInspection> inspectSource(
    SkillSourceInput source,
  ) {
    inspectedSources.add(source);
    if (inspectionFailure != null && inspectedSources.length == 1) {
      return WorkspaceTask(
        current: WorkspaceOperationProgress(
          operationId: 'inspect',
          kind: WorkspaceOperationKind.inspectSource,
          phase: WorkspaceOperationPhase.inspecting,
        ),
        states: StreamController<WorkspaceOperationProgress>(
          onCancel: () async {},
        ).stream,
        cancel: () async {},
        completed: Future.value(
          WorkspaceFailed(
            failure: WorkspaceFailure(
              code: inspectionFailure!,
              operation: WorkspaceOperationKind.inspectSource,
              context: inspectionFailureContext,
            ),
          ),
        ),
      );
    }
    return task(
      'inspect',
      () => WorkspaceSourceInspection(source: source, candidates: candidates),
    );
  }

  @override
  WorkspaceTask<WorkspaceInstallAttempt> install(
    WorkspaceInstallRequest request,
  ) {
    installRequests.add(request);
    return task('install', () {
      if (occupied) return WorkspaceInstallTakeoverRequired(_InstallDraft());
      final candidate = candidates.singleWhere(
        (c) => request.skillNames!.contains(c.declaredName),
      );
      final skill = testSkill(
        id: 'installed-${candidate.slotKey}',
        slot: candidate.slotKey,
      );
      current = SkillsWorkspaceSnapshot(
        revision: current.revision + 1,
        skills: [...current.skills, skill],
        projectRoots: current.projectRoots,
      );
      publications.add(current);
      onPublish?.call();
      return WorkspaceInstallCompleted(
        WorkspaceMutationReceipt(
          snapshot: current,
          affectedSkillIds: {skill.id},
        ),
      );
    });
  }

  @override
  WorkspaceTask<WorkspaceMutationReceipt> update({
    Set<WorkspaceSkillId>? skillIds,
  }) {
    skillSets.add(skillIds ?? {});
    return task('update', () {
      if (conflictAfterUpdate) {
        current = SkillsWorkspaceSnapshot(
          revision: current.revision + 1,
          projectRoots: current.projectRoots,
          skills: [
            for (final s in current.skills)
              if (skillIds == null || skillIds.contains(s.id))
                s.copyWith(
                  updateCandidate: WorkspaceUpdateCandidateSummary(
                    status: WorkspaceUpdateCandidateStatus.conflicted,
                    conflictPaths: ['SKILL.md'],
                    createdAt: DateTime.utc(2026),
                  ),
                )
              else
                s,
          ],
        );
        publications.add(current);
        onPublish?.call();
      }
      return receipt();
    });
  }

  @override
  WorkspaceTask<List<WorkspaceUpdateReport>> checkUpdates({
    Set<WorkspaceSkillId>? skillIds,
  }) => task(
    'check',
    () => updateReports
        .where((r) => skillIds == null || skillIds.contains(r.skillId))
        .toList(),
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Draft implements WorkspaceActivationTakeoverDraft {
  @override
  int get expectedRevision => 7;
  @override
  List<WorkspaceOccupiedActivationTarget> get targets => [];
}

final class _InstallDraft implements WorkspaceInstallTakeoverDraft {
  @override
  int get expectedRevision => 7;
  @override
  List<WorkspaceOccupiedActivationTarget> get targets => [];
}
