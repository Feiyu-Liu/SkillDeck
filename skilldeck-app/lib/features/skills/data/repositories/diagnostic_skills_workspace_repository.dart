import 'package:skills_manager/features/skills/data/repositories/skills_workspace_repository.dart';
import 'package:skills_manager/features/skills/models/external_skills.dart';
import 'package:skills_manager/features/skills/models/skill_document.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/shared/diagnostics/app_diagnostics.dart';
import 'package:skills_manager/shared/failures/app_failure_reporter.dart';

final class DiagnosticSkillsWorkspaceRepository
    implements SkillsWorkspaceRepository, SkillsUpdateCheckStore {
  const DiagnosticSkillsWorkspaceRepository({
    required SkillsWorkspaceRepository delegate,
    required AppDiagnostics diagnostics,
    required AppFailureReporter failureReporter,
  }) : _delegate = delegate,
       _diagnostics = diagnostics,
       _failureReporter = failureReporter;

  final SkillsWorkspaceRepository _delegate;
  final AppDiagnostics _diagnostics;
  final AppFailureReporter _failureReporter;

  @override
  Future<WorkspaceUpdateCacheSnapshot> readUpdateCache() {
    final store = _delegate;
    if (store case final SkillsUpdateCheckStore updateStore) {
      return updateStore.readUpdateCache();
    }
    return Future.value(WorkspaceUpdateCacheSnapshot(records: []));
  }

  @override
  Future<void> upsertUpdateCache(WorkspaceUpdateCacheRecord record) {
    final store = _delegate;
    if (store case final SkillsUpdateCheckStore updateStore) {
      return updateStore.upsertUpdateCache(record);
    }
    return Future<void>.value();
  }

  @override
  Future<void> removeUpdateCache(WorkspaceSkillId skillId) {
    final store = _delegate;
    if (store case final SkillsUpdateCheckStore updateStore) {
      return updateStore.removeUpdateCache(skillId);
    }
    return Future<void>.value();
  }

  @override
  Future<void> writeLastFullUpdateSweepAt(DateTime value) {
    final store = _delegate;
    if (store case final SkillsUpdateCheckStore updateStore) {
      return updateStore.writeLastFullUpdateSweepAt(value);
    }
    return Future<void>.value();
  }

  @override
  SkillsWorkspaceSnapshot? get current => _delegate.current;

  @override
  WorkspaceTask<WorkspaceSkillDriftReview> inspectSkillDrift(
    WorkspaceSkillId skillId,
  ) => _traceTask(
    WorkspaceOperationKind.inspectSkillDrift,
    () => _delegate.inspectSkillDrift(skillId),
    startContext: {'skillId': skillId.value},
    successContext: (review) => {
      'artifactCount': review.artifacts.length,
      'missingArtifactCount': review.missingArtifactCount,
    },
  );

  @override
  WorkspaceTask<WorkspaceSkillDriftExport> exportSkillDriftArtifact({
    required WorkspaceSkillDriftReview review,
    required String artifactId,
    required String destinationDirectory,
  }) => _traceTask(
    WorkspaceOperationKind.exportSkillDriftArtifact,
    () => _delegate.exportSkillDriftArtifact(
      review: review,
      artifactId: artifactId,
      destinationDirectory: destinationDirectory,
    ),
    startContext: {'skillId': review.skillId.value, 'artifactId': artifactId},
  );

  @override
  WorkspaceTask<WorkspaceMutationReceipt> resolveSkillDrift({
    required WorkspaceSkillDriftReview review,
    required WorkspaceDriftResolution resolution,
  }) => _traceTask(
    WorkspaceOperationKind.resolveSkillDrift,
    () => _delegate.resolveSkillDrift(review: review, resolution: resolution),
    startContext: {
      'skillId': review.skillId.value,
      'resolution': resolution is WorkspaceKeepExternalSkillDrift
          ? 'keepExternal'
          : 'restoreManaged',
    },
    successContext: (receipt) => {'revision': receipt.snapshot.revision},
  );

  @override
  Stream<SkillsWorkspaceSnapshot> get snapshots => _delegate.snapshots;

  @override
  Future<WorkspaceCompletion<SkillsWorkspaceSnapshot>> open() =>
      _traceCompletion(
        WorkspaceOperationKind.open,
        _delegate.open,
        successContext: (snapshot) => {'revision': snapshot.revision},
      );

  @override
  Future<WorkspaceCompletion<SkillsWorkspaceSnapshot>> refresh() =>
      _traceCompletion(
        WorkspaceOperationKind.refresh,
        _delegate.refresh,
        successContext: (snapshot) => {'revision': snapshot.revision},
      );

  @override
  WorkspaceTask<WorkspaceValidationReport> validateWorkspace({
    Set<WorkspaceSkillId>? skillIds,
  }) => _traceTask(
    WorkspaceOperationKind.validateWorkspace,
    () => _delegate.validateWorkspace(skillIds: skillIds),
    successContext: (report) => {
      'checkedSkillCount': report.checkedSkillCount,
      'driftedSkillCount': report.driftedSkillIds.length,
      'failedSkillCount': report.failedSkillIds.length,
    },
  );

  @override
  WorkspaceTask<SkillsWorkspaceSnapshot> resumeFinalizationRecovery() =>
      _traceTask(
        WorkspaceOperationKind.resumeFinalizationRecovery,
        _delegate.resumeFinalizationRecovery,
        successContext: (snapshot) => {'revision': snapshot.revision},
      );

  @override
  Future<WorkspaceCompletion<List<SkillDocumentEntry>>> listSkillDocuments(
    WorkspaceSkillId skillId,
  ) => _traceCompletion(
    WorkspaceOperationKind.readDocument,
    () => _delegate.listSkillDocuments(skillId),
    startContext: {'skillId': skillId.value},
    successContext: (documents) => {'documentCount': documents.length},
  );

  @override
  Future<WorkspaceCompletion<String>> readSkillDocument(
    WorkspaceSkillId skillId,
    String relativePath, {
    required String expectedContentHash,
  }) => _traceCompletion(
    WorkspaceOperationKind.readDocument,
    () => _delegate.readSkillDocument(
      skillId,
      relativePath,
      expectedContentHash: expectedContentHash,
    ),
    startContext: {
      'skillId': skillId.value,
      'relativePath': relativePath,
      'expectedContentHash': expectedContentHash,
    },
  );

  @override
  WorkspaceTask<WorkspaceSourceInspection> inspectSource(
    SkillSourceInput source,
  ) => _traceTask(
    WorkspaceOperationKind.inspectSource,
    () => _delegate.inspectSource(source),
    startContext: {'sourceKind': source.kind.name},
    successContext: (inspection) => {
      'candidateCount': inspection.candidates.length,
    },
  );

  @override
  Future<WorkspaceGitEnvironmentStatus> probeGitEnvironment() =>
      _delegate.probeGitEnvironment();

  @override
  WorkspaceTask<List<WorkspaceAgentInfo>> inspectAgents() => _traceTask(
    WorkspaceOperationKind.inspectAgents,
    _delegate.inspectAgents,
    successContext: (agents) => {'agentCount': agents.length},
  );

  @override
  WorkspaceTask<List<WorkspaceActivationTarget>> inspectActivationTargets({
    required WorkspaceScope scope,
    String? projectRootId,
  }) => _traceTask(
    WorkspaceOperationKind.inspectActivationTargets,
    () => _delegate.inspectActivationTargets(
      scope: scope,
      projectRootId: projectRootId,
    ),
    startContext: {'scope': scope.name, 'projectRootId': ?projectRootId},
    successContext: (targets) => {'targetCount': targets.length},
  );

  @override
  WorkspaceTask<WorkspaceAgentRootOwnershipAudit> inspectAgentRootOwnership() =>
      _traceTask(
        WorkspaceOperationKind.inspectAgentRootOwnership,
        _delegate.inspectAgentRootOwnership,
        successContext: (audit) => {
          'supported': audit.supported,
          'examinedRootCount': audit.examinedRootCount,
          'issueCount': audit.issues.length,
        },
      );

  @override
  WorkspaceTask<ExternalSkillsDiscovery> discoverExternalSkills() => _traceTask(
    WorkspaceOperationKind.discoverExternalSkills,
    _delegate.discoverExternalSkills,
    successContext: (discovery) => {
      'candidateCount': discovery.candidates.length,
      'conflictCount': discovery.conflicts.length,
    },
  );

  @override
  WorkspaceTask<WorkspaceInstallAttempt> install(
    WorkspaceInstallRequest request,
  ) => _traceTask(
    WorkspaceOperationKind.install,
    () => _delegate.install(request),
    startContext: {
      'sourceKind': request.source.kind.name,
      'scope': request.scope.name,
      'storeOnly': request.storeOnly,
      'selectedSkillCount': request.skillNames?.length ?? 'all',
      'agentCount': request.agentIds.length,
      'activationMethod': request.activationMethod.name,
    },
    successContext: (attempt) => {
      'takeoverRequired': attempt is WorkspaceInstallTakeoverRequired,
    },
  );

  @override
  WorkspaceTask<WorkspaceMutationReceipt> confirmInstallTakeover(
    WorkspaceInstallTakeoverDraft draft,
  ) => _traceMutation(
    WorkspaceOperationKind.confirmInstallTakeover,
    () => _delegate.confirmInstallTakeover(draft),
    startContext: {'targetCount': draft.targets.length},
  );

  @override
  WorkspaceTask<WorkspaceMutationReceipt> adopt(
    ExternalSkillAdoptionRequest request,
  ) => _traceMutation(
    WorkspaceOperationKind.adopt,
    () => _delegate.adopt(request),
    startContext: {'slotKey': request.slotKey},
  );

  @override
  WorkspaceTask<WorkspaceMutationReceipt> replaceSource({
    required WorkspaceSkillId skillId,
    required SkillSourceInput source,
    required int expectedRevision,
  }) => _traceMutation(
    WorkspaceOperationKind.replaceSource,
    () => _delegate.replaceSource(
      skillId: skillId,
      source: source,
      expectedRevision: expectedRevision,
    ),
    startContext: {
      'skillId': skillId.value,
      'sourceKind': source.kind.name,
      'expectedRevision': expectedRevision,
    },
  );

  @override
  WorkspaceTask<WorkspaceActivationAttempt> activate({
    required Set<WorkspaceSkillId> skillIds,
    required WorkspaceScope scope,
    required Set<String> agentIds,
    String? projectRootId,
    WorkspaceActivationMethod activationMethod =
        WorkspaceActivationMethod.automatic,
  }) => _traceTask(
    WorkspaceOperationKind.activate,
    () => _delegate.activate(
      skillIds: skillIds,
      scope: scope,
      agentIds: agentIds,
      projectRootId: projectRootId,
      activationMethod: activationMethod,
    ),
    startContext: {
      'skillCount': skillIds.length,
      'scope': scope.name,
      'agentCount': agentIds.length,
      'projectRootId': ?projectRootId,
      'activationMethod': activationMethod.name,
    },
    successContext: (attempt) => switch (attempt) {
      WorkspaceActivationCompleted(:final receipt) => {
        'revision': receipt.snapshot.revision,
        'affectedSkillCount': receipt.affectedSkillIds.length,
      },
      WorkspaceActivationTakeoverRequired(:final draft) => {
        'takeoverTargetCount': draft.targets.length,
      },
    },
  );

  @override
  WorkspaceTask<WorkspaceMutationReceipt> confirmActivationTakeover(
    WorkspaceActivationTakeoverDraft draft,
  ) => _traceMutation(
    WorkspaceOperationKind.confirmActivationTakeover,
    () => _delegate.confirmActivationTakeover(draft),
    startContext: {'targetCount': draft.targets.length},
  );

  @override
  WorkspaceTask<WorkspaceMutationReceipt> deactivate({
    required Set<WorkspaceSkillId> skillIds,
    Set<String>? locations,
  }) => _traceMutation(
    WorkspaceOperationKind.deactivate,
    () => _delegate.deactivate(skillIds: skillIds, locations: locations),
    startContext: {
      'skillCount': skillIds.length,
      if (locations != null) 'locationCount': locations.length,
    },
  );

  @override
  WorkspaceTask<WorkspaceMutationReceipt> remove({
    required Set<WorkspaceSkillId> skillIds,
    required int expectedRevision,
  }) => _traceMutation(
    WorkspaceOperationKind.remove,
    () => _delegate.remove(
      skillIds: skillIds,
      expectedRevision: expectedRevision,
    ),
    startContext: {
      'skillCount': skillIds.length,
      'expectedRevision': expectedRevision,
    },
  );

  @override
  WorkspaceTask<List<WorkspaceUpdateReport>> checkUpdates({
    Set<WorkspaceSkillId>? skillIds,
  }) => _traceTask(
    WorkspaceOperationKind.checkUpdates,
    () => _delegate.checkUpdates(skillIds: skillIds),
    startContext: {'skillCount': skillIds?.length ?? 'all'},
    successContext: (reports) => {'reportCount': reports.length},
  );

  @override
  WorkspaceTask<WorkspaceMutationReceipt> update({
    Set<WorkspaceSkillId>? skillIds,
  }) => _traceMutation(
    WorkspaceOperationKind.update,
    () => _delegate.update(skillIds: skillIds),
    startContext: {'skillCount': skillIds?.length ?? 'all'},
  );

  @override
  WorkspaceTask<WorkspaceMutationReceipt> registerProjectRoot({
    required String path,
    String? id,
  }) => _traceMutation(
    WorkspaceOperationKind.registerProjectRoot,
    () => _delegate.registerProjectRoot(path: path, id: id),
    startContext: {'projectRootId': ?id},
  );

  @override
  WorkspaceTask<WorkspaceMutationReceipt> unregisterProjectRoot(String id) =>
      _traceMutation(
        WorkspaceOperationKind.unregisterProjectRoot,
        () => _delegate.unregisterProjectRoot(id),
        startContext: {'projectRootId': id},
      );

  @override
  WorkspaceTask<SkillsWorkspaceSnapshot> reconfigureAgentCatalog(
    List<WorkspaceAgentDefinition> agents,
  ) => _traceTask(
    WorkspaceOperationKind.reconfigureAgentCatalog,
    () => _delegate.reconfigureAgentCatalog(agents),
    startContext: {'agentCount': agents.length},
    successContext: (snapshot) => {'revision': snapshot.revision},
  );

  @override
  WorkspaceTask<SkillsWorkspaceSnapshot> setFavorite({
    required WorkspaceSkillId skillId,
    required bool isFavorite,
  }) => _traceTask(
    WorkspaceOperationKind.setFavorite,
    () => _delegate.setFavorite(skillId: skillId, isFavorite: isFavorite),
    startContext: {'skillId': skillId.value, 'isFavorite': isFavorite},
    successContext: (snapshot) => {'revision': snapshot.revision},
  );

  @override
  WorkspaceTask<SkillsWorkspaceSnapshot> saveNote({
    required WorkspaceSkillId skillId,
    required String note,
  }) => _traceTask(
    WorkspaceOperationKind.saveNote,
    () => _delegate.saveNote(skillId: skillId, note: note),
    startContext: {'skillId': skillId.value},
    successContext: (snapshot) => {'revision': snapshot.revision},
  );

  @override
  WorkspaceTask<SkillsWorkspaceSnapshot> deleteNote(WorkspaceSkillId skillId) =>
      _traceTask(
        WorkspaceOperationKind.deleteNote,
        () => _delegate.deleteNote(skillId),
        startContext: {'skillId': skillId.value},
        successContext: (snapshot) => {'revision': snapshot.revision},
      );

  // Tag names are user-authored, so traces carry only opaque identities.
  @override
  WorkspaceTask<WorkspacePersonalTag> createPersonalTag({
    required String name,
    String? color,
  }) => _traceTask(
    WorkspaceOperationKind.createPersonalTag,
    () => _delegate.createPersonalTag(name: name, color: color),
    successContext: (tag) => {'tagId': tag.id},
  );

  @override
  WorkspaceTask<WorkspacePersonalTag> updatePersonalTag({
    required String tagId,
    required String name,
    String? color,
  }) => _traceTask(
    WorkspaceOperationKind.updatePersonalTag,
    () => _delegate.updatePersonalTag(tagId: tagId, name: name, color: color),
    startContext: {'tagId': tagId},
    successContext: (tag) => {'tagId': tag.id},
  );

  @override
  WorkspaceTask<SkillsWorkspaceSnapshot> deletePersonalTag(String tagId) =>
      _traceTask(
        WorkspaceOperationKind.deletePersonalTag,
        () => _delegate.deletePersonalTag(tagId),
        startContext: {'tagId': tagId},
        successContext: (snapshot) => {'revision': snapshot.revision},
      );

  @override
  WorkspaceTask<SkillsWorkspaceSnapshot> assignPersonalTag({
    required WorkspaceSkillId skillId,
    required String tagId,
  }) => _traceTask(
    WorkspaceOperationKind.assignPersonalTag,
    () => _delegate.assignPersonalTag(skillId: skillId, tagId: tagId),
    startContext: {'skillId': skillId.value, 'tagId': tagId},
    successContext: (snapshot) => {'revision': snapshot.revision},
  );

  @override
  WorkspaceTask<SkillsWorkspaceSnapshot> unassignPersonalTag({
    required WorkspaceSkillId skillId,
    required String tagId,
  }) => _traceTask(
    WorkspaceOperationKind.unassignPersonalTag,
    () => _delegate.unassignPersonalTag(skillId: skillId, tagId: tagId),
    startContext: {'skillId': skillId.value, 'tagId': tagId},
    successContext: (snapshot) => {'revision': snapshot.revision},
  );

  @override
  WorkspaceTask<SkillsWorkspaceSnapshot> abandonUpdateCandidate(
    WorkspaceSkillId skillId,
  ) => _traceTask(
    WorkspaceOperationKind.abandonUpdateCandidate,
    () => _delegate.abandonUpdateCandidate(skillId),
    startContext: {'skillId': skillId.value},
    successContext: (snapshot) => {'revision': snapshot.revision},
  );

  @override
  Future<void> close() async {
    final stopwatch = Stopwatch()..start();
    _diagnostics.operationStarted(
      operationKey: WorkspaceOperationKind.close.name,
    );
    try {
      await _delegate.close();
      stopwatch.stop();
      _diagnostics.operationSucceeded(
        operationKey: WorkspaceOperationKind.close.name,
        duration: stopwatch.elapsed,
      );
    } on Object catch (error, stackTrace) {
      stopwatch.stop();
      _failureReporter.capture(
        error,
        stackTrace,
        operationKey: WorkspaceOperationKind.close.name,
        duration: stopwatch.elapsed,
      );
      rethrow;
    }
  }

  WorkspaceTask<WorkspaceMutationReceipt> _traceMutation(
    WorkspaceOperationKind kind,
    WorkspaceTask<WorkspaceMutationReceipt> Function() create, {
    Map<String, Object?> startContext = const {},
  }) => _traceTask(
    kind,
    create,
    startContext: startContext,
    successContext: (receipt) => {
      'revision': receipt.snapshot.revision,
      'affectedSkillCount': receipt.affectedSkillIds.length,
    },
  );

  WorkspaceTask<T> _traceTask<T>(
    WorkspaceOperationKind kind,
    WorkspaceTask<T> Function() create, {
    Map<String, Object?> startContext = const {},
    Map<String, Object?> Function(T value)? successContext,
  }) {
    final stopwatch = Stopwatch()..start();
    WorkspaceTask<T> task;
    try {
      task = create();
    } on Object catch (error, stackTrace) {
      stopwatch.stop();
      _diagnostics.operationStarted(
        operationKey: kind.name,
        context: startContext,
      );
      _failureReporter.capture(
        error,
        stackTrace,
        operationKey: kind.name,
        duration: stopwatch.elapsed,
      );
      rethrow;
    }
    final operationId = task.current.operationId;
    _diagnostics.operationStarted(
      operationKey: kind.name,
      operationId: operationId,
      context: startContext,
    );
    return WorkspaceTask(
      current: task.current,
      states: task.states,
      completed: _traceTaskCompletion(
        kind,
        operationId,
        stopwatch,
        task.completed,
        successContext,
      ),
      cancel: () async {
        _diagnostics.cancellationRequested(
          operationKey: kind.name,
          operationId: operationId,
        );
        try {
          await task.cancel();
        } on Object catch (error, stackTrace) {
          _failureReporter.capture(
            error,
            stackTrace,
            operationKey: kind.name,
            operationId: operationId,
            duration: stopwatch.elapsed,
          );
          rethrow;
        }
      },
    );
  }

  Future<WorkspaceCompletion<T>> _traceCompletion<T>(
    WorkspaceOperationKind kind,
    Future<WorkspaceCompletion<T>> Function() run, {
    Map<String, Object?> startContext = const {},
    Map<String, Object?> Function(T value)? successContext,
  }) async {
    final stopwatch = Stopwatch()..start();
    _diagnostics.operationStarted(
      operationKey: kind.name,
      context: startContext,
    );
    try {
      final completion = await run();
      stopwatch.stop();
      switch (completion) {
        case WorkspaceCompleted(:final value):
          _diagnostics.operationSucceeded(
            operationKey: kind.name,
            duration: stopwatch.elapsed,
            context: successContext?.call(value) ?? const {},
          );
        case WorkspaceCommittedPending():
          _diagnostics.operationSucceeded(
            operationKey: kind.name,
            duration: stopwatch.elapsed,
            context: const {'finalizationPending': true},
          );
        case WorkspaceFailed(:final failure):
          _diagnostics.failure(
            error: failure,
            failure: failure,
            operationKey: kind.name,
            duration: stopwatch.elapsed,
          );
      }
      return completion;
    } on Object catch (error, stackTrace) {
      stopwatch.stop();
      _failureReporter.capture(
        error,
        stackTrace,
        operationKey: kind.name,
        duration: stopwatch.elapsed,
      );
      rethrow;
    }
  }

  Future<WorkspaceCompletion<T>> _traceTaskCompletion<T>(
    WorkspaceOperationKind kind,
    String operationId,
    Stopwatch stopwatch,
    Future<WorkspaceCompletion<T>> completed,
    Map<String, Object?> Function(T value)? successContext,
  ) async {
    try {
      final completion = await completed;
      stopwatch.stop();
      switch (completion) {
        case WorkspaceCompleted(:final value):
          _diagnostics.operationSucceeded(
            operationKey: kind.name,
            operationId: operationId,
            duration: stopwatch.elapsed,
            context: successContext?.call(value) ?? const {},
          );
        case WorkspaceCommittedPending(:final operationId):
          _diagnostics.operationSucceeded(
            operationKey: kind.name,
            operationId: operationId,
            duration: stopwatch.elapsed,
            context: const {'finalizationPending': true},
          );
        case WorkspaceFailed(:final failure):
          _diagnostics.failure(
            error: failure,
            failure: failure,
            operationKey: kind.name,
            operationId: operationId,
            duration: stopwatch.elapsed,
          );
      }
      return completion;
    } on Object catch (error, stackTrace) {
      stopwatch.stop();
      _failureReporter.capture(
        error,
        stackTrace,
        operationKey: kind.name,
        operationId: operationId,
        duration: stopwatch.elapsed,
      );
      rethrow;
    }
  }
}
