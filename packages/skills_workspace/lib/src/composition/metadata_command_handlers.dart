import '../api/composite_command_dispatcher.dart';
import '../api/requests.dart';
import '../api/result.dart';
import '../application/library/library_mutation_planner.dart';
import '../application/operations/operation_coordinator.dart';
import '../application/operations/operation_plan_assembler.dart';
import '../application/ports/external_discovery_ports.dart';
import '../application/project_roots/project_root_planner.dart';
import '../application/runtime/workspace_snapshot_publisher.dart';
import '../domain/identifiers.dart';
import '../domain/public_models.dart';
import 'mutation_command_support.dart';

/// Builds the Project Root and Library mutation slice.
///
/// These operations change only SQLite-authoritative business state, but they
/// still use the same Journal, Repository Revision, Business Commit Point and
/// recovery path as filesystem/revision mutations.
List<SkillsCommandHandler> buildMetadataCommandHandlers({
  required WorkspaceSnapshotPublisher snapshots,
  required OperationCoordinator operations,
  required OperationPlanAssembler plans,
  required ProjectRootPlanner projectRoots,
  required LibraryMutationPlanner library,
  required WorkspaceClockPort clock,
}) => <SkillsCommandHandler>[
  TypedSkillsCommandHandler<RegisterProjectRootRequest, MutationReport>(
    kind: WorkspaceOperationKind.registerProjectRoot,
    handle: (request, context) async {
      context.reportProgress(OperationProgressPhase.inspecting);
      final snapshot = snapshots.current;
      final planned = await projectRoots.register(
        snapshot: snapshot,
        candidatePath: request.path,
        requestedId: request.id,
      );
      final failure = planned.failureOrNull;
      if (failure != null) return _projectRootFailure(failure);
      final plan = planned.valueOrNull!;
      if (!plan.changed) {
        return SkillsSuccess<MutationReport>(
          value: MutationReport(snapshot: snapshot, affectedSkillIds: const {}),
          changed: false,
        );
      }
      return executeMutation<MutationReport>(
        context: context,
        planningSnapshot: snapshot,
        operations: operations,
        buildPlan: (operationId, revision) => plans.sqliteOnly(
          operationId: operationId,
          expectedRepositoryRevision: revision,
          kind: WorkspaceOperationKind.registerProjectRoot,
          businessChanges: plan.changeSet,
          retainWithoutSubjects: true,
        ),
        snapshots: snapshots,
        valueFromSnapshot: (committed) =>
            MutationReport(snapshot: committed, affectedSkillIds: const {}),
      );
    },
  ),
  TypedSkillsCommandHandler<UnregisterProjectRootRequest, MutationReport>(
    kind: WorkspaceOperationKind.unregisterProjectRoot,
    handle: (request, context) async {
      context.reportProgress(OperationProgressPhase.inspecting);
      final snapshot = snapshots.current;
      final planned = projectRoots.unregister(
        snapshot: snapshot,
        projectRootId: request.id,
      );
      final failure = planned.failureOrNull;
      if (failure != null) return _projectRootFailure(failure);
      final plan = planned.valueOrNull!;
      return executeMutation<MutationReport>(
        context: context,
        planningSnapshot: snapshot,
        operations: operations,
        buildPlan: (operationId, revision) => plans.sqliteOnly(
          operationId: operationId,
          expectedRepositoryRevision: revision,
          kind: WorkspaceOperationKind.unregisterProjectRoot,
          businessChanges: plan.changeSet,
          retainWithoutSubjects: true,
        ),
        snapshots: snapshots,
        valueFromSnapshot: (committed) =>
            MutationReport(snapshot: committed, affectedSkillIds: const {}),
      );
    },
  ),
  TypedSkillsCommandHandler<SetFavoriteRequest, RepositorySnapshot>(
    kind: WorkspaceOperationKind.setFavorite,
    handle: (request, context) => _runLibrary<void, RepositorySnapshot>(
      context: context,
      snapshots: snapshots,
      operations: operations,
      plans: plans,
      kind: WorkspaceOperationKind.setFavorite,
      managedSkillIds: <ManagedSkillId>{request.managedSkillId},
      plan: (snapshot) => library.setFavorite(
        snapshot: snapshot,
        managedSkillId: request.managedSkillId,
        isFavorite: request.isFavorite,
        changedAt: clock.now(),
      ),
      valueFromSnapshot: (snapshot, _) => snapshot,
    ),
  ),
  TypedSkillsCommandHandler<SaveNoteRequest, RepositorySnapshot>(
    kind: WorkspaceOperationKind.saveNote,
    handle: (request, context) => _runLibrary<void, RepositorySnapshot>(
      context: context,
      snapshots: snapshots,
      operations: operations,
      plans: plans,
      kind: WorkspaceOperationKind.saveNote,
      managedSkillIds: <ManagedSkillId>{request.managedSkillId},
      plan: (snapshot) => library.saveNote(
        snapshot: snapshot,
        managedSkillId: request.managedSkillId,
        text: request.text,
        updatedAt: clock.now(),
      ),
      valueFromSnapshot: (snapshot, _) => snapshot,
    ),
  ),
  TypedSkillsCommandHandler<DeleteNoteRequest, RepositorySnapshot>(
    kind: WorkspaceOperationKind.deleteNote,
    handle: (request, context) => _runLibrary<void, RepositorySnapshot>(
      context: context,
      snapshots: snapshots,
      operations: operations,
      plans: plans,
      kind: WorkspaceOperationKind.deleteNote,
      managedSkillIds: <ManagedSkillId>{request.managedSkillId},
      plan: (snapshot) => library.deleteNote(
        snapshot: snapshot,
        managedSkillId: request.managedSkillId,
      ),
      valueFromSnapshot: (snapshot, _) => snapshot,
    ),
  ),
  TypedSkillsCommandHandler<CreatePersonalTagRequest, PersonalTag>(
    kind: WorkspaceOperationKind.createPersonalTag,
    handle: (request, context) => _runLibrary<PersonalTag, PersonalTag>(
      context: context,
      snapshots: snapshots,
      operations: operations,
      plans: plans,
      kind: WorkspaceOperationKind.createPersonalTag,
      managedSkillIds: const <ManagedSkillId>{},
      plan: (snapshot) => library.createTag(
        snapshot: snapshot,
        name: request.name,
        color: request.color,
        createdAt: clock.now(),
      ),
      valueFromSnapshot: (snapshot, planned) =>
          snapshot.findPersonalTag(planned.id)!,
    ),
  ),
  TypedSkillsCommandHandler<UpdatePersonalTagRequest, PersonalTag>(
    kind: WorkspaceOperationKind.updatePersonalTag,
    handle: (request, context) => _runLibrary<PersonalTag, PersonalTag>(
      context: context,
      snapshots: snapshots,
      operations: operations,
      plans: plans,
      kind: WorkspaceOperationKind.updatePersonalTag,
      managedSkillIds: const <ManagedSkillId>{},
      plan: (snapshot) => library.updateTag(
        snapshot: snapshot,
        tagId: request.tagId,
        name: request.name,
        color: request.color,
        updatedAt: clock.now(),
      ),
      valueFromSnapshot: (snapshot, planned) =>
          snapshot.findPersonalTag(planned.id)!,
    ),
  ),
  TypedSkillsCommandHandler<DeletePersonalTagRequest, RepositorySnapshot>(
    kind: WorkspaceOperationKind.deletePersonalTag,
    handle: (request, context) {
      final affected = <ManagedSkillId>{
        for (final skill in snapshots.current.managedSkills)
          if (skill.personalTagIds.contains(request.tagId)) skill.id,
      };
      return _runLibrary<void, RepositorySnapshot>(
        context: context,
        snapshots: snapshots,
        operations: operations,
        plans: plans,
        kind: WorkspaceOperationKind.deletePersonalTag,
        managedSkillIds: affected,
        plan: (snapshot) =>
            library.deleteTag(snapshot: snapshot, tagId: request.tagId),
        valueFromSnapshot: (snapshot, _) => snapshot,
      );
    },
  ),
  TypedSkillsCommandHandler<AssignPersonalTagRequest, RepositorySnapshot>(
    kind: WorkspaceOperationKind.assignPersonalTag,
    handle: (request, context) => _runLibrary<void, RepositorySnapshot>(
      context: context,
      snapshots: snapshots,
      operations: operations,
      plans: plans,
      kind: WorkspaceOperationKind.assignPersonalTag,
      managedSkillIds: <ManagedSkillId>{request.managedSkillId},
      plan: (snapshot) => library.assignTag(
        snapshot: snapshot,
        managedSkillId: request.managedSkillId,
        tagId: request.tagId,
        createdAt: clock.now(),
      ),
      valueFromSnapshot: (snapshot, _) => snapshot,
    ),
  ),
  TypedSkillsCommandHandler<UnassignPersonalTagRequest, RepositorySnapshot>(
    kind: WorkspaceOperationKind.unassignPersonalTag,
    handle: (request, context) => _runLibrary<void, RepositorySnapshot>(
      context: context,
      snapshots: snapshots,
      operations: operations,
      plans: plans,
      kind: WorkspaceOperationKind.unassignPersonalTag,
      managedSkillIds: <ManagedSkillId>{request.managedSkillId},
      plan: (snapshot) => library.unassignTag(
        snapshot: snapshot,
        managedSkillId: request.managedSkillId,
        tagId: request.tagId,
      ),
      valueFromSnapshot: (snapshot, _) => snapshot,
    ),
  ),
];

typedef _LibraryPlan<T> =
    LibraryPlanningResult<T> Function(RepositorySnapshot snapshot);

Future<SkillsResult<TResult>> _runLibrary<TPlan, TResult>({
  required SkillsCommandContext context,
  required WorkspaceSnapshotPublisher snapshots,
  required OperationCoordinator operations,
  required OperationPlanAssembler plans,
  required WorkspaceOperationKind kind,
  required Set<ManagedSkillId> managedSkillIds,
  required _LibraryPlan<TPlan> plan,
  required TResult Function(RepositorySnapshot snapshot, TPlan plannedValue)
  valueFromSnapshot,
}) async {
  context.reportProgress(OperationProgressPhase.inspecting);
  final snapshot = snapshots.current;
  final result = plan(snapshot);
  if (result is LibraryPlanningFailure<TPlan>) {
    return _libraryFailure<TResult>(result.code);
  }
  final planned = result as LibraryMutationPlan<TPlan>;
  if (!planned.changed) {
    return SkillsSuccess<TResult>(
      value: valueFromSnapshot(snapshot, planned.value),
      changed: false,
    );
  }
  final subjects = <OperationSubjectIntent>[
    for (final managedSkillId in managedSkillIds)
      if (snapshot.findSkill(managedSkillId) case final skill?) _subject(skill),
  ];
  return executeMutation<TResult>(
    context: context,
    planningSnapshot: snapshot,
    operations: operations,
    buildPlan: (operationId, revision) => plans.sqliteOnly(
      operationId: operationId,
      expectedRepositoryRevision: revision,
      kind: kind,
      businessChanges: planned.changes,
      subjects: subjects,
      retainWithoutSubjects: subjects.isEmpty,
    ),
    snapshots: snapshots,
    valueFromSnapshot: (committed) =>
        valueFromSnapshot(committed, planned.value),
  );
}

OperationSubjectIntent _subject(ManagedSkill skill) => OperationSubjectIntent(
  managedSkillId: skill.id,
  displayName: skill.displayName,
  beforeContentHash: skill.currentRevision.contentHash,
  afterContentHash: skill.currentRevision.contentHash,
);

SkillsFailure<T> _libraryFailure<T>(LibraryPlanningFailureCode code) =>
    SkillsFailure<T>(
      code: switch (code) {
        LibraryPlanningFailureCode.managedSkillNotFound =>
          SkillsErrorCode.skillNotFound,
        LibraryPlanningFailureCode.personalTagNotFound =>
          SkillsErrorCode.personalTagNotFound,
        LibraryPlanningFailureCode.duplicatePersonalTag =>
          SkillsErrorCode.duplicatePersonalTag,
      },
      context: <String, Object?>{'reason': code.name},
    );

SkillsFailure<T> _projectRootFailure<T>(
  ProjectRootFailure<Object?> failure,
) => SkillsFailure<T>(
  code: switch (failure.code) {
    ProjectRootFailureCode.invalidPath => SkillsErrorCode.invalidProjectRoot,
    ProjectRootFailureCode.projectRootNotFound =>
      SkillsErrorCode.projectRootNotFound,
    ProjectRootFailureCode.projectRootIdConflict ||
    ProjectRootFailureCode.projectRootPathConflict =>
      SkillsErrorCode.projectRootConflict,
  },
  context: <String, Object?>{'reason': failure.code.name, ...failure.context},
);
