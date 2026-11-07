import '../../domain/public_models.dart';
import '../operations/workspace_business_changes.dart';
import '../ports/agent_activation_ports.dart';
import '../ports/external_discovery_ports.dart';

enum ProjectRootFailureCode {
  invalidPath,
  projectRootIdConflict,
  projectRootPathConflict,
  projectRootNotFound,
}

sealed class ProjectRootResult<T> {
  const ProjectRootResult();

  T? get valueOrNull;
  ProjectRootFailure<T>? get failureOrNull;
}

final class ProjectRootSuccess<T> extends ProjectRootResult<T> {
  const ProjectRootSuccess({required this.value});

  final T value;

  @override
  T get valueOrNull => value;

  @override
  ProjectRootFailure<T>? get failureOrNull => null;
}

final class ProjectRootFailure<T> extends ProjectRootResult<T> {
  ProjectRootFailure({
    required this.code,
    Map<String, Object?> context = const <String, Object?>{},
  }) : context = Map.unmodifiable(context);

  final ProjectRootFailureCode code;
  final Map<String, Object?> context;

  @override
  T? get valueOrNull => null;

  @override
  ProjectRootFailure<T> get failureOrNull => this;
}

final class ProjectRootMutationPlan {
  const ProjectRootMutationPlan({
    required this.changeSet,
    required this.projectRoot,
  });

  final WorkspaceBusinessChangeSet changeSet;
  final ProjectRoot projectRoot;

  bool get changed => !changeSet.isEmpty;
}

/// Validates Project Root invariants and emits persistence-neutral changes.
final class ProjectRootPlanner {
  const ProjectRootPlanner({
    required ProjectRootPathPort pathPort,
    required ActivationLocationIdentityPort locationIdentity,
    required ProjectRootIdPort idPort,
    required WorkspaceClockPort clock,
  }) : _pathPort = pathPort,
       _locationIdentity = locationIdentity,
       _idPort = idPort,
       _clock = clock;

  final ProjectRootPathPort _pathPort;
  final ActivationLocationIdentityPort _locationIdentity;
  final ProjectRootIdPort _idPort;
  final WorkspaceClockPort _clock;

  Future<ProjectRootResult<ProjectRootMutationPlan>> register({
    required RepositorySnapshot snapshot,
    required String candidatePath,
    String? requestedId,
  }) async {
    final canonicalPath = await _pathPort.canonicalizeExistingDirectory(
      candidatePath,
    );
    if (canonicalPath == null) {
      return ProjectRootFailure<ProjectRootMutationPlan>(
        code: ProjectRootFailureCode.invalidPath,
        context: <String, Object?>{'path': candidatePath},
      );
    }
    final id =
        requestedId ??
        _idPort.allocate(<String>{
          for (final root in snapshot.projectRoots) root.id,
        });
    final existingById = snapshot.findProjectRoot(id);
    if (existingById != null) {
      if (_locationIdentity.key(existingById.path) ==
          _locationIdentity.key(canonicalPath)) {
        return ProjectRootSuccess<ProjectRootMutationPlan>(
          value: ProjectRootMutationPlan(
            changeSet: WorkspaceBusinessChangeSet.empty,
            projectRoot: existingById,
          ),
        );
      }
      return ProjectRootFailure<ProjectRootMutationPlan>(
        code: ProjectRootFailureCode.projectRootIdConflict,
        context: <String, Object?>{'projectRootId': id},
      );
    }
    for (final root in snapshot.projectRoots) {
      if (_locationIdentity.key(root.path) ==
          _locationIdentity.key(canonicalPath)) {
        return ProjectRootFailure<ProjectRootMutationPlan>(
          code: ProjectRootFailureCode.projectRootPathConflict,
          context: <String, Object?>{'projectRootId': root.id},
        );
      }
    }

    final projectRoot = ProjectRoot(id: id, path: canonicalPath);
    final timestamp = _clock.now().toUtc().microsecondsSinceEpoch;
    return ProjectRootSuccess<ProjectRootMutationPlan>(
      value: ProjectRootMutationPlan(
        changeSet: WorkspaceBusinessChangeSet(
          mutations: <WorkspaceBusinessMutation>[
            PutProjectRoot(
              projectRootId: projectRoot.id,
              canonicalPath: projectRoot.path,
              createdAtMicros: timestamp,
              updatedAtMicros: timestamp,
            ),
          ],
        ),
        projectRoot: projectRoot,
      ),
    );
  }

  ProjectRootResult<ProjectRootMutationPlan> unregister({
    required RepositorySnapshot snapshot,
    required String projectRootId,
  }) {
    final root = snapshot.findProjectRoot(projectRootId);
    if (root == null) {
      return ProjectRootFailure<ProjectRootMutationPlan>(
        code: ProjectRootFailureCode.projectRootNotFound,
        context: <String, Object?>{'projectRootId': projectRootId},
      );
    }
    return ProjectRootSuccess<ProjectRootMutationPlan>(
      value: ProjectRootMutationPlan(
        changeSet: WorkspaceBusinessChangeSet(
          mutations: <WorkspaceBusinessMutation>[
            DeleteProjectRoot(projectRootId),
          ],
        ),
        projectRoot: root,
      ),
    );
  }
}
