import 'dart:async';

import 'package:skills_manager/features/skills/data/repositories/skills_workspace_repository.dart';
import 'package:skills_manager/features/skills/models/external_skills.dart';
import 'package:skills_manager/features/skills/models/skill_document.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';

import 'fake_skill_drift_reviews.dart';

final class FakeWorkspaceActivationTakeoverDraft
    implements WorkspaceActivationTakeoverDraft {
  FakeWorkspaceActivationTakeoverDraft({
    this.expectedRevision = 0,
    required List<WorkspaceOccupiedActivationTarget> targets,
  }) : targets = List.unmodifiable(targets);

  @override
  final int expectedRevision;

  @override
  final List<WorkspaceOccupiedActivationTarget> targets;
}

final class FakeWorkspaceInstallTakeoverDraft
    implements WorkspaceInstallTakeoverDraft {
  FakeWorkspaceInstallTakeoverDraft({
    this.expectedRevision = 0,
    required List<WorkspaceOccupiedActivationTarget> targets,
  }) : targets = List.unmodifiable(targets);

  @override
  final int expectedRevision;

  @override
  final List<WorkspaceOccupiedActivationTarget> targets;
}

final class FakeSkillsWorkspaceRepository implements SkillsWorkspaceRepository {
  FakeSkillsWorkspaceRepository({
    SkillsWorkspaceSnapshot? snapshot,
    Map<String, String>? documents,
    List<WorkspaceActivationTarget> globalTargets = const [],
    Map<String, List<WorkspaceActivationTarget>> projectTargets =
        const <String, List<WorkspaceActivationTarget>>{},
    List<WorkspaceUpdateReport> updateReports = const [],
    ExternalSkillsDiscovery? externalSkillsDiscovery,
  }) : _current = snapshot ?? SkillsWorkspaceSnapshot.empty(),
       documents = {...?documents},
       globalTargets = List.unmodifiable(globalTargets),
       projectTargets =
           Map<String, List<WorkspaceActivationTarget>>.unmodifiable({
             for (final entry in projectTargets.entries)
               entry.key: List<WorkspaceActivationTarget>.unmodifiable(
                 entry.value,
               ),
           }),
       updateReports = List.unmodifiable(updateReports),
       externalSkillsDiscovery =
           externalSkillsDiscovery ?? ExternalSkillsDiscovery.empty();

  final StreamController<SkillsWorkspaceSnapshot> _snapshots =
      StreamController<SkillsWorkspaceSnapshot>.broadcast();
  SkillsWorkspaceSnapshot _current;

  final Map<String, String> documents;
  final List<WorkspaceActivationTarget> globalTargets;
  final Map<String, List<WorkspaceActivationTarget>> projectTargets;
  List<WorkspaceUpdateReport> updateReports;
  ExternalSkillsDiscovery externalSkillsDiscovery;
  WorkspaceSourceInspection? sourceInspection;

  /// Host Git capability the fake reports, plus a gate and a counter so tests
  /// can observe the in-flight frame and prove nothing probes on its own.
  WorkspaceGitEnvironmentStatus gitEnvironmentStatus =
      WorkspaceGitEnvironmentStatus.available;
  Completer<void>? gitEnvironmentGate;
  Object? gitEnvironmentError;
  int gitEnvironmentProbeCount = 0;

  WorkspaceException? openError;
  Completer<WorkspaceCompletion<SkillsWorkspaceSnapshot>>? openCompleter;
  WorkspaceException? refreshError;
  Completer<WorkspaceCompletion<SkillsWorkspaceSnapshot>>? refreshCompleter;
  WorkspaceException? listDocumentsError;
  WorkspaceException? readDocumentError;
  WorkspaceException? inspectActivationTargetsError;
  WorkspaceAgentRootOwnershipAudit ownershipAudit =
      WorkspaceAgentRootOwnershipAudit(
        supported: true,
        currentUserId: 501,
        examinedRootCount: 0,
        issues: const [],
      );
  final List<WorkspaceAgentRootOwnershipAudit> ownershipAudits = [];
  int ownershipInspections = 0;
  SkillsWorkspaceSnapshot? refreshSnapshot;
  SkillsWorkspaceSnapshot? resolveSkillDriftSnapshot;
  WorkspaceSkillIntegrityStatus? resolveSkillDriftIntegrity;
  WorkspaceException? registerError;
  WorkspaceException? unregisterError;
  WorkspaceException? removeError;
  WorkspaceException? updateError;
  WorkspaceException? checkUpdatesError;
  WorkspaceException? discoverExternalSkillsError;
  WorkspaceException? adoptError;
  final sourceInspections = <String, WorkspaceSourceInspection>{};
  final inspectSourceErrors = <String, WorkspaceException>{};
  WorkspaceException? inspectSourceError;
  WorkspaceException? replaceSourceError;
  WorkspaceException? activateError;
  WorkspaceException? confirmActivationTakeoverError;
  Object? closeError;
  WorkspaceActivationAttempt? activateAttempt;
  WorkspaceTask<WorkspaceActivationAttempt>? activateTask;
  WorkspaceInstallAttempt? installAttempt;
  WorkspaceException? confirmInstallTakeoverError;
  WorkspaceTask<ExternalSkillsDiscovery>? discoverExternalSkillsTask;
  WorkspaceTask<WorkspaceMutationReceipt> Function(
    ExternalSkillAdoptionRequest request,
  )?
  adoptTaskBuilder;
  WorkspaceTask<List<WorkspaceUpdateReport>>? checkUpdatesTask;

  /// Per-call hook, so a test can observe or gate each individual check.
  /// `checkUpdatesTask` stays a single shared task for the simple cases.
  WorkspaceTask<List<WorkspaceUpdateReport>> Function(
    Set<WorkspaceSkillId>? skillIds,
  )?
  checkUpdatesTaskBuilder;
  WorkspaceTask<WorkspaceMutationReceipt>? updateTask;
  WorkspaceTask<WorkspaceMutationReceipt>? removeTask;
  WorkspaceTask<SkillsWorkspaceSnapshot>? favoriteTask;
  WorkspaceTask<WorkspacePersonalTag>? createPersonalTagTask;
  WorkspaceTask<WorkspacePersonalTag>? updatePersonalTagTask;
  WorkspaceTask<SkillsWorkspaceSnapshot>? assignPersonalTagTask;
  WorkspaceTask<SkillsWorkspaceSnapshot>? reconfigureAgentCatalogTask;
  final List<WorkspaceTask<SkillsWorkspaceSnapshot>> finalizationRecoveryTasks =
      [];

  final List<WorkspaceTask<WorkspaceSkillDriftReview>> inspectSkillDriftTasks =
      [];
  final List<WorkspaceTask<WorkspaceSkillDriftExport>>
  exportSkillDriftArtifactTasks = [];
  final List<WorkspaceTask<WorkspaceMutationReceipt>> resolveSkillDriftTasks =
      [];
  final List<WorkspaceSkillId> inspectedSkillDrifts = [];
  final List<
    ({
      WorkspaceSkillDriftReview review,
      String artifactId,
      String destinationDirectory,
    })
  >
  exportedSkillDriftArtifacts = [];
  final List<
    ({WorkspaceSkillDriftReview review, WorkspaceDriftResolution resolution})
  >
  resolvedSkillDrifts = [];

  int openCalls = 0;
  int refreshCalls = 0;
  int finalizationRecoveryCalls = 0;
  int closeCalls = 0;
  int checkUpdatesCalls = 0;
  final List<Set<WorkspaceSkillId>?> checkUpdatesRequests = [];
  int discoverExternalSkillsCalls = 0;
  final List<String> documentReads = [];
  final List<({WorkspaceScope scope, String? projectRootId})>
  targetInspections = [];
  final List<SkillSourceInput> inspectedSources = [];
  final List<WorkspaceInstallRequest> installRequests = [];
  final List<WorkspaceInstallTakeoverDraft> confirmedInstallTakeovers = [];
  final List<({String path, String? id})> registrations = [];
  final List<String> unregistrations = [];
  final List<
    ({
      Set<String> slotKeys,
      WorkspaceScope scope,
      Set<String> agentIds,
      String? projectRootId,
      WorkspaceActivationMethod activationMethod,
    })
  >
  activations = [];
  final List<({Set<String> slotKeys, Set<String>? locations})> deactivations =
      [];
  final List<WorkspaceActivationTakeoverDraft> confirmedTakeovers = [];
  final List<({Set<String> slotKeys, int expectedRevision})> removals = [];
  final List<Set<String>?> updateRequests = [];
  final List<ExternalSkillAdoptionRequest> adoptionRequests = [];
  final List<List<WorkspaceAgentDefinition>> agentCatalogReconfigurations = [];
  final List<({WorkspaceSkillId skillId, bool isFavorite})> favoriteRequests =
      [];
  final List<({WorkspaceSkillId skillId, String note})> noteRequests = [];
  final List<WorkspaceSkillId> deletedNotes = [];
  final List<({String name, String? color})> createdPersonalTags = [];
  final List<({String tagId, String name, String? color})> updatedPersonalTags =
      [];
  final List<String> deletedPersonalTags = [];
  final List<({WorkspaceSkillId skillId, String tagId})> assignedPersonalTags =
      [];
  final List<({WorkspaceSkillId skillId, String tagId})>
  unassignedPersonalTags = [];
  int _nextPersonalTagId = 1;
  final List<WorkspaceSkillId> abandonedUpdateCandidates = [];
  final List<({String slotKey, SkillSourceInput source, int expectedRevision})>
  replaceSourceRequests = [];

  @override
  SkillsWorkspaceSnapshot get current => _current;

  @override
  Stream<SkillsWorkspaceSnapshot> get snapshots => _snapshots.stream;

  void publish(SkillsWorkspaceSnapshot snapshot) {
    _commitSnapshot(snapshot);
  }

  /// Publishes advisory validation evidence without a business revision bump.
  void publishIntegrity({
    WorkspaceIntegrityStatus? integrity,
    Map<WorkspaceSkillId, WorkspaceSkillIntegrityStatus> skills = const {},
  }) {
    _commitSnapshot(
      SkillsWorkspaceSnapshot(
        revision: _current.revision,
        projectRoots: _current.projectRoots,
        personalTags: _current.personalTags,
        integrity: integrity ?? _current.integrity,
        skills: [
          for (final skill in _current.skills)
            if (skills[skill.id] case final status?)
              WorkspaceSkill(
                id: skill.id,
                slotKey: skill.slotKey,
                declaredName: skill.declaredName,
                displayName: skill.displayName,
                description: skill.description,
                source: skill.source,
                currentRevision: skill.currentRevision,
                activations: skill.activations,
                isFavorite: skill.isFavorite,
                note: skill.note,
                personalTagIds: skill.personalTagIds,
                integrity: status,
                draft: skill.draft,
                updateCandidate: skill.updateCandidate,
              )
            else
              skill,
        ],
      ),
    );
  }

  @override
  Future<WorkspaceCompletion<SkillsWorkspaceSnapshot>> open() {
    openCalls += 1;
    final error = openError;
    if (error != null) {
      return failedWorkspaceTask<SkillsWorkspaceSnapshot>(
        kind: WorkspaceOperationKind.open,
        error: error,
      ).completed;
    }
    final completer = openCompleter;
    if (completer != null) return completer.future;
    return completedWorkspaceTask<SkillsWorkspaceSnapshot>(
      kind: WorkspaceOperationKind.open,
      value: _current,
    ).completed;
  }

  @override
  Future<WorkspaceCompletion<SkillsWorkspaceSnapshot>> refresh() {
    refreshCalls += 1;
    final deferred = refreshCompleter;
    if (deferred != null) return deferred.future;
    final error = refreshError;
    if (error != null) {
      return failedWorkspaceTask<SkillsWorkspaceSnapshot>(
        kind: WorkspaceOperationKind.refresh,
        error: error,
      ).completed;
    }
    final next = refreshSnapshot;
    if (next != null) _commitSnapshot(next);
    return completedWorkspaceTask<SkillsWorkspaceSnapshot>(
      kind: WorkspaceOperationKind.refresh,
      value: _current,
    ).completed;
  }

  /// Tasks returned, in order, by [validateWorkspace] before it falls back to
  /// an immediately completed empty report.
  final validationTasks = <WorkspaceTask<WorkspaceValidationReport>>[];

  @override
  WorkspaceTask<WorkspaceValidationReport> validateWorkspace({
    Set<WorkspaceSkillId>? skillIds,
  }) => validationTasks.isNotEmpty
      ? validationTasks.removeAt(0)
      : completedWorkspaceTask(
          kind: WorkspaceOperationKind.validateWorkspace,
          value: WorkspaceValidationReport(
            checkedSkillCount: 0,
            repairedArtifactCount: 0,
            healthySkillCount: 0,
            repairedSkillIds: [],
            driftedSkillIds: [],
            failedSkillIds: [],
          ),
        );

  @override
  WorkspaceTask<SkillsWorkspaceSnapshot> resumeFinalizationRecovery() {
    finalizationRecoveryCalls += 1;
    if (finalizationRecoveryTasks.isNotEmpty) {
      return finalizationRecoveryTasks.removeAt(0);
    }
    return completedWorkspaceTask(
      kind: WorkspaceOperationKind.resumeFinalizationRecovery,
      value: _current,
    );
  }

  @override
  Future<WorkspaceCompletion<List<SkillDocumentEntry>>> listSkillDocuments(
    WorkspaceSkillId skillId,
  ) {
    final error = listDocumentsError;
    if (error != null) {
      return failedWorkspaceTask<List<SkillDocumentEntry>>(
        kind: WorkspaceOperationKind.readDocument,
        error: error,
      ).completed;
    }
    return completedWorkspaceTask<List<SkillDocumentEntry>>(
      kind: WorkspaceOperationKind.readDocument,
      value: [
        if (documents.containsKey(_slotKeyOf(skillId)))
          SkillDocumentEntry(
            relativePath: 'SKILL.md',
            name: 'SKILL.md',
            contentHash:
                _current.findSkillById(skillId)?.currentRevision.contentHash ??
                '',
          ),
      ],
    ).completed;
  }

  @override
  Future<WorkspaceCompletion<String>> readSkillDocument(
    WorkspaceSkillId skillId,
    String relativePath, {
    required String expectedContentHash,
  }) {
    documentReads.add(_slotKeyOf(skillId));
    final error = readDocumentError;
    if (error != null) {
      return failedWorkspaceTask<String>(
        kind: WorkspaceOperationKind.readDocument,
        error: error,
      ).completed;
    }
    final document = relativePath == 'SKILL.md'
        ? documents[_slotKeyOf(skillId)]
        : null;
    if (document == null) {
      return failedWorkspaceTask<String>(
        kind: WorkspaceOperationKind.readDocument,
        error: WorkspaceException(
          code: WorkspaceErrorCode.documentUnavailable,
          operation: WorkspaceOperationKind.readDocument,
        ),
      ).completed;
    }
    return completedWorkspaceTask<String>(
      kind: WorkspaceOperationKind.readDocument,
      value: document,
    ).completed;
  }

  @override
  WorkspaceTask<WorkspaceSourceInspection> inspectSource(
    SkillSourceInput source,
  ) {
    inspectedSources.add(source);
    final error = inspectSourceErrors[source.locator] ?? inspectSourceError;
    if (error != null) {
      return failedWorkspaceTask(
        kind: WorkspaceOperationKind.inspectSource,
        error: error,
      );
    }
    return completedWorkspaceTask(
      kind: WorkspaceOperationKind.inspectSource,
      value:
          sourceInspections[source.locator] ??
          sourceInspection ??
          WorkspaceSourceInspection(source: source, candidates: const []),
    );
  }

  @override
  Future<WorkspaceGitEnvironmentStatus> probeGitEnvironment() async {
    gitEnvironmentProbeCount += 1;
    final gate = gitEnvironmentGate;
    if (gate != null) await gate.future;
    final error = gitEnvironmentError;
    if (error != null) throw error;
    return gitEnvironmentStatus;
  }

  @override
  WorkspaceTask<List<WorkspaceAgentInfo>> inspectAgents() {
    final targets = [
      ...globalTargets,
      for (final items in projectTargets.values) ...items,
    ];
    return completedWorkspaceTask(
      kind: WorkspaceOperationKind.inspectAgents,
      value: [
        for (final id in targets.map((t) => t.agentId).toSet())
          if (id != 'universal')
            WorkspaceAgentInfo(
              id: id,
              displayName: targets
                  .firstWhere((t) => t.agentId == id)
                  .displayName,
              isBuiltIn: !id.startsWith('custom-'),
              supportedScopes: {
                for (final t in targets)
                  if (t.agentId == id) t.scope,
              },
              detectedGlobally: targets.any(
                (t) =>
                    t.agentId == id &&
                    t.detected &&
                    t.scope == WorkspaceScope.global,
              ),
              detectedProjectRootIds: {
                for (final t in targets)
                  if (t.agentId == id && t.detected && t.projectRootId != null)
                    t.projectRootId!,
              },
            ),
      ],
    );
  }

  @override
  WorkspaceTask<List<WorkspaceActivationTarget>> inspectActivationTargets({
    required WorkspaceScope scope,
    String? projectRootId,
  }) {
    targetInspections.add((scope: scope, projectRootId: projectRootId));
    final error = inspectActivationTargetsError;
    if (error != null) {
      return failedWorkspaceTask(
        kind: WorkspaceOperationKind.inspectActivationTargets,
        error: error,
      );
    }
    final targets = scope == WorkspaceScope.global
        ? globalTargets
        : projectTargets[projectRootId] ?? const [];
    return completedWorkspaceTask(
      kind: WorkspaceOperationKind.inspectActivationTargets,
      value: targets,
    );
  }

  @override
  WorkspaceTask<WorkspaceAgentRootOwnershipAudit> inspectAgentRootOwnership() {
    ownershipInspections += 1;
    return completedWorkspaceTask(
      kind: WorkspaceOperationKind.inspectAgentRootOwnership,
      value: ownershipAudits.isEmpty
          ? ownershipAudit
          : ownershipAudits.removeAt(0),
    );
  }

  @override
  WorkspaceTask<ExternalSkillsDiscovery> discoverExternalSkills() {
    discoverExternalSkillsCalls += 1;
    final task = discoverExternalSkillsTask;
    if (task != null) return task;
    final error = discoverExternalSkillsError;
    if (error != null) {
      return failedWorkspaceTask(
        kind: WorkspaceOperationKind.discoverExternalSkills,
        error: error,
      );
    }
    return completedWorkspaceTask(
      kind: WorkspaceOperationKind.discoverExternalSkills,
      value: externalSkillsDiscovery,
    );
  }

  @override
  WorkspaceTask<WorkspaceInstallAttempt> install(
    WorkspaceInstallRequest request,
  ) {
    installRequests.add(request);
    return completedWorkspaceTask(
      kind: WorkspaceOperationKind.install,
      value:
          installAttempt ??
          WorkspaceInstallCompleted(_receipt(request.skillNames ?? const {})),
    );
  }

  @override
  WorkspaceTask<WorkspaceMutationReceipt> confirmInstallTakeover(
    WorkspaceInstallTakeoverDraft draft,
  ) {
    confirmedInstallTakeovers.add(draft);
    final error = confirmInstallTakeoverError;
    if (error != null) {
      return failedWorkspaceTask(
        kind: WorkspaceOperationKind.confirmInstallTakeover,
        error: error,
      );
    }
    return completedWorkspaceTask(
      kind: WorkspaceOperationKind.confirmInstallTakeover,
      value: _receipt({for (final target in draft.targets) target.slotKey}),
    );
  }

  @override
  WorkspaceTask<WorkspaceMutationReceipt> adopt(
    ExternalSkillAdoptionRequest request,
  ) {
    adoptionRequests.add(request);
    final taskBuilder = adoptTaskBuilder;
    if (taskBuilder != null) return taskBuilder(request);
    final error = adoptError;
    if (error != null) {
      return failedWorkspaceTask(
        kind: WorkspaceOperationKind.adopt,
        error: error,
      );
    }
    return completedWorkspaceTask(
      kind: WorkspaceOperationKind.adopt,
      value: _receipt({request.slotKey}),
    );
  }

  @override
  WorkspaceTask<WorkspaceMutationReceipt> replaceSource({
    required WorkspaceSkillId skillId,
    required SkillSourceInput source,
    required int expectedRevision,
  }) {
    replaceSourceRequests.add((
      slotKey: _slotKeyOf(skillId),
      source: source,
      expectedRevision: expectedRevision,
    ));
    final error = replaceSourceError;
    if (error != null) {
      return failedWorkspaceTask(
        kind: WorkspaceOperationKind.replaceSource,
        error: error,
      );
    }
    return completedWorkspaceTask(
      kind: WorkspaceOperationKind.replaceSource,
      value: _receipt({_slotKeyOf(skillId)}),
    );
  }

  @override
  WorkspaceTask<WorkspaceActivationAttempt> activate({
    required Set<WorkspaceSkillId> skillIds,
    required WorkspaceScope scope,
    required Set<String> agentIds,
    String? projectRootId,
    WorkspaceActivationMethod activationMethod =
        WorkspaceActivationMethod.automatic,
  }) {
    activations.add((
      slotKeys: {for (final id in skillIds) _slotKeyOf(id)},
      scope: scope,
      agentIds: Set.unmodifiable(agentIds),
      projectRootId: projectRootId,
      activationMethod: activationMethod,
    ));
    final task = activateTask;
    if (task != null) return task;
    final error = activateError;
    if (error != null) {
      return failedWorkspaceTask(
        kind: WorkspaceOperationKind.activate,
        error: error,
      );
    }
    return completedWorkspaceTask(
      kind: WorkspaceOperationKind.activate,
      value:
          activateAttempt ??
          WorkspaceActivationCompleted(
            _receipt({for (final id in skillIds) _slotKeyOf(id)}),
          ),
    );
  }

  @override
  WorkspaceTask<WorkspaceMutationReceipt> confirmActivationTakeover(
    WorkspaceActivationTakeoverDraft draft,
  ) {
    confirmedTakeovers.add(draft);
    final error = confirmActivationTakeoverError;
    if (error != null) {
      return failedWorkspaceTask(
        kind: WorkspaceOperationKind.confirmActivationTakeover,
        error: error,
      );
    }
    return completedWorkspaceTask(
      kind: WorkspaceOperationKind.confirmActivationTakeover,
      value: _receipt({for (final target in draft.targets) target.slotKey}),
    );
  }

  @override
  WorkspaceTask<WorkspaceMutationReceipt> deactivate({
    required Set<WorkspaceSkillId> skillIds,
    Set<String>? locations,
  }) {
    deactivations.add((
      slotKeys: {for (final id in skillIds) _slotKeyOf(id)},
      locations: locations == null ? null : Set.unmodifiable(locations),
    ));
    return completedWorkspaceTask(
      kind: WorkspaceOperationKind.deactivate,
      value: _receipt({for (final id in skillIds) _slotKeyOf(id)}),
    );
  }

  @override
  WorkspaceTask<WorkspaceMutationReceipt> remove({
    required Set<WorkspaceSkillId> skillIds,
    required int expectedRevision,
  }) {
    removals.add((
      slotKeys: {for (final id in skillIds) _slotKeyOf(id)},
      expectedRevision: expectedRevision,
    ));
    final task = removeTask;
    if (task != null) return task;
    final error = removeError;
    if (error != null) {
      return failedWorkspaceTask(
        kind: WorkspaceOperationKind.remove,
        error: error,
      );
    }
    return completedWorkspaceTask(
      kind: WorkspaceOperationKind.remove,
      value: _receipt({for (final id in skillIds) _slotKeyOf(id)}),
    );
  }

  @override
  WorkspaceTask<List<WorkspaceUpdateReport>> checkUpdates({
    Set<WorkspaceSkillId>? skillIds,
  }) {
    checkUpdatesCalls += 1;
    checkUpdatesRequests.add(skillIds);
    final builder = checkUpdatesTaskBuilder;
    if (builder != null) return builder(skillIds);
    final task = checkUpdatesTask;
    if (task != null) return task;
    final error = checkUpdatesError;
    if (error != null) {
      return failedWorkspaceTask(
        kind: WorkspaceOperationKind.checkUpdates,
        error: error,
      );
    }
    final reports = skillIds == null
        ? updateReports
        : updateReports
              .where((report) => skillIds.contains(report.skillId))
              .toList();
    return completedWorkspaceTask(
      kind: WorkspaceOperationKind.checkUpdates,
      value: reports,
    );
  }

  @override
  WorkspaceTask<WorkspaceMutationReceipt> update({
    Set<WorkspaceSkillId>? skillIds,
  }) {
    updateRequests.add(
      skillIds == null ? null : {for (final id in skillIds) _slotKeyOf(id)},
    );
    final task = updateTask;
    if (task != null) return task;
    final error = updateError;
    if (error != null) {
      return failedWorkspaceTask(
        kind: WorkspaceOperationKind.update,
        error: error,
      );
    }
    return completedWorkspaceTask(
      kind: WorkspaceOperationKind.update,
      value: _receipt({
        for (final id in skillIds ?? const <WorkspaceSkillId>{}) _slotKeyOf(id),
      }),
    );
  }

  @override
  WorkspaceTask<WorkspaceMutationReceipt> registerProjectRoot({
    required String path,
    String? id,
  }) {
    registrations.add((path: path, id: id));
    final error = registerError;
    if (error != null) {
      return failedWorkspaceTask(
        kind: WorkspaceOperationKind.registerProjectRoot,
        error: error,
      );
    }
    final rootId = id ?? 'project-${_current.projectRoots.length + 1}';
    _commitSnapshot(
      SkillsWorkspaceSnapshot(
        revision: _current.revision + 1,
        projectRoots: [
          ..._current.projectRoots,
          SkillProjectRoot(id: rootId, path: path),
        ],
        skills: _current.skills,
      ),
    );
    return completedWorkspaceTask(
      kind: WorkspaceOperationKind.registerProjectRoot,
      value: _receipt(const {}),
    );
  }

  @override
  WorkspaceTask<WorkspaceMutationReceipt> unregisterProjectRoot(String id) {
    unregistrations.add(id);
    final error = unregisterError;
    if (error != null) {
      return failedWorkspaceTask(
        kind: WorkspaceOperationKind.unregisterProjectRoot,
        error: error,
      );
    }
    _commitSnapshot(
      SkillsWorkspaceSnapshot(
        revision: _current.revision + 1,
        projectRoots: [
          for (final root in _current.projectRoots)
            if (root.id != id) root,
        ],
        skills: _current.skills,
      ),
    );
    return completedWorkspaceTask(
      kind: WorkspaceOperationKind.unregisterProjectRoot,
      value: _receipt(const {}),
    );
  }

  @override
  WorkspaceTask<SkillsWorkspaceSnapshot> reconfigureAgentCatalog(
    List<WorkspaceAgentDefinition> agents,
  ) {
    agentCatalogReconfigurations.add(List.unmodifiable(agents));
    final task = reconfigureAgentCatalogTask;
    if (task != null) return task;
    return completedWorkspaceTask(
      kind: WorkspaceOperationKind.reconfigureAgentCatalog,
      value: _current,
    );
  }

  @override
  WorkspaceTask<SkillsWorkspaceSnapshot> setFavorite({
    required WorkspaceSkillId skillId,
    required bool isFavorite,
  }) {
    favoriteRequests.add((skillId: skillId, isFavorite: isFavorite));
    final task = favoriteTask;
    if (task != null) return task;
    _replaceSkill(skillId, (skill) => skill.copyWith(isFavorite: isFavorite));
    return completedWorkspaceTask(
      kind: WorkspaceOperationKind.setFavorite,
      value: _current,
    );
  }

  @override
  WorkspaceTask<SkillsWorkspaceSnapshot> saveNote({
    required WorkspaceSkillId skillId,
    required String note,
  }) {
    noteRequests.add((skillId: skillId, note: note));
    _replaceSkill(skillId, (skill) => skill.copyWith(note: note));
    return completedWorkspaceTask(
      kind: WorkspaceOperationKind.saveNote,
      value: _current,
    );
  }

  @override
  WorkspaceTask<SkillsWorkspaceSnapshot> deleteNote(WorkspaceSkillId skillId) {
    deletedNotes.add(skillId);
    final existing = _current.findSkillById(skillId);
    // Match the package's no-op for an already absent Note: focus changes must
    // not manufacture a business revision that hides integrity delivery bugs.
    if (existing == null || existing.note != null) {
      _replaceSkill(skillId, (skill) => skill.copyWith(note: null));
    }
    return completedWorkspaceTask(
      kind: WorkspaceOperationKind.deleteNote,
      value: _current,
    );
  }

  @override
  WorkspaceTask<WorkspacePersonalTag> createPersonalTag({
    required String name,
    String? color,
  }) {
    createdPersonalTags.add((name: name, color: color));
    const kind = WorkspaceOperationKind.createPersonalTag;
    final task = createPersonalTagTask;
    if (task != null) return task;
    if (_personalTagNamed(name) != null) {
      return _personalTagFailure(kind, WorkspaceErrorCode.duplicatePersonalTag);
    }
    final now = DateTime.utc(2026);
    final tag = WorkspacePersonalTag(
      id: 'tag-${_nextPersonalTagId++}',
      name: name.trim(),
      color: color,
      createdAt: now,
      updatedAt: now,
    );
    _replacePersonalTags([..._current.personalTags, tag]);
    return completedWorkspaceTask(kind: kind, value: tag);
  }

  @override
  WorkspaceTask<WorkspacePersonalTag> updatePersonalTag({
    required String tagId,
    required String name,
    String? color,
  }) {
    updatedPersonalTags.add((tagId: tagId, name: name, color: color));
    const kind = WorkspaceOperationKind.updatePersonalTag;
    final task = updatePersonalTagTask;
    if (task != null) return task;
    final existing = _current.findPersonalTag(tagId);
    if (existing == null) {
      return _personalTagFailure(kind, WorkspaceErrorCode.personalTagNotFound);
    }
    final collision = _personalTagNamed(name);
    if (collision != null && collision.id != tagId) {
      return _personalTagFailure(kind, WorkspaceErrorCode.duplicatePersonalTag);
    }
    final tag = WorkspacePersonalTag(
      id: tagId,
      name: name.trim(),
      color: color,
      createdAt: existing.createdAt,
      updatedAt: existing.updatedAt,
    );
    _replacePersonalTags([
      for (final current in _current.personalTags)
        if (current.id == tagId) tag else current,
    ]);
    return completedWorkspaceTask(kind: kind, value: tag);
  }

  @override
  WorkspaceTask<SkillsWorkspaceSnapshot> deletePersonalTag(String tagId) {
    deletedPersonalTags.add(tagId);
    const kind = WorkspaceOperationKind.deletePersonalTag;
    if (_current.findPersonalTag(tagId) == null) {
      return _personalTagFailure(kind, WorkspaceErrorCode.personalTagNotFound);
    }
    _commitSnapshot(
      SkillsWorkspaceSnapshot(
        revision: _current.revision + 1,
        projectRoots: _current.projectRoots,
        personalTags: [
          for (final tag in _current.personalTags)
            if (tag.id != tagId) tag,
        ],
        integrity: _current.integrity,
        skills: [
          for (final skill in _current.skills)
            skill.personalTagIds.contains(tagId)
                ? skill.copyWith(
                    personalTagIds: [
                      for (final id in skill.personalTagIds)
                        if (id != tagId) id,
                    ],
                  )
                : skill,
        ],
      ),
    );
    return completedWorkspaceTask(kind: kind, value: _current);
  }

  @override
  WorkspaceTask<SkillsWorkspaceSnapshot> assignPersonalTag({
    required WorkspaceSkillId skillId,
    required String tagId,
  }) {
    assignedPersonalTags.add((skillId: skillId, tagId: tagId));
    const kind = WorkspaceOperationKind.assignPersonalTag;
    final task = assignPersonalTagTask;
    if (task != null) return task;
    if (_current.findPersonalTag(tagId) == null) {
      return _personalTagFailure(kind, WorkspaceErrorCode.personalTagNotFound);
    }
    _replaceSkill(
      skillId,
      (skill) => skill.personalTagIds.contains(tagId)
          ? skill
          : skill.copyWith(personalTagIds: [...skill.personalTagIds, tagId]),
    );
    return completedWorkspaceTask(kind: kind, value: _current);
  }

  @override
  WorkspaceTask<SkillsWorkspaceSnapshot> unassignPersonalTag({
    required WorkspaceSkillId skillId,
    required String tagId,
  }) {
    unassignedPersonalTags.add((skillId: skillId, tagId: tagId));
    _replaceSkill(
      skillId,
      (skill) => skill.copyWith(
        personalTagIds: [
          for (final id in skill.personalTagIds)
            if (id != tagId) id,
        ],
      ),
    );
    return completedWorkspaceTask(
      kind: WorkspaceOperationKind.unassignPersonalTag,
      value: _current,
    );
  }

  WorkspacePersonalTag? _personalTagNamed(String name) {
    final key = name.trim().toUpperCase();
    for (final tag in _current.personalTags) {
      if (tag.name.toUpperCase() == key) return tag;
    }
    return null;
  }

  WorkspaceTask<T> _personalTagFailure<T>(
    WorkspaceOperationKind kind,
    WorkspaceErrorCode code,
  ) => failedWorkspaceTask(
    kind: kind,
    error: WorkspaceException(code: code, operation: kind),
  );

  void _replacePersonalTags(List<WorkspacePersonalTag> tags) {
    _commitSnapshot(
      SkillsWorkspaceSnapshot(
        revision: _current.revision + 1,
        projectRoots: _current.projectRoots,
        skills: _current.skills,
        personalTags: tags,
        integrity: _current.integrity,
      ),
    );
  }

  @override
  WorkspaceTask<SkillsWorkspaceSnapshot> abandonUpdateCandidate(
    WorkspaceSkillId skillId,
  ) {
    abandonedUpdateCandidates.add(skillId);
    _replaceSkill(skillId, (skill) => skill.copyWith(updateCandidate: null));
    return completedWorkspaceTask(
      kind: WorkspaceOperationKind.abandonUpdateCandidate,
      value: _current,
    );
  }

  @override
  Future<void> close() async {
    closeCalls += 1;
    final error = closeError;
    if (error != null) throw error;
    await _snapshots.close();
  }

  @override
  WorkspaceTask<WorkspaceSkillDriftReview> inspectSkillDrift(
    WorkspaceSkillId skillId,
  ) {
    inspectedSkillDrifts.add(skillId);
    if (inspectSkillDriftTasks.isNotEmpty) {
      return inspectSkillDriftTasks.removeAt(0);
    }
    return completedWorkspaceTask(
      kind: WorkspaceOperationKind.inspectSkillDrift,
      value: FakeWorkspaceSkillDriftReview(skillId: skillId),
    );
  }

  @override
  WorkspaceTask<WorkspaceSkillDriftExport> exportSkillDriftArtifact({
    required WorkspaceSkillDriftReview review,
    required String artifactId,
    required String destinationDirectory,
  }) {
    exportedSkillDriftArtifacts.add((
      review: review,
      artifactId: artifactId,
      destinationDirectory: destinationDirectory,
    ));
    if (exportSkillDriftArtifactTasks.isNotEmpty) {
      return exportSkillDriftArtifactTasks.removeAt(0);
    }
    return completedWorkspaceTask(
      kind: WorkspaceOperationKind.exportSkillDriftArtifact,
      value: WorkspaceSkillDriftExport(
        exportedPath: '$destinationDirectory/external',
      ),
    );
  }

  @override
  WorkspaceTask<WorkspaceMutationReceipt> resolveSkillDrift({
    required WorkspaceSkillDriftReview review,
    required WorkspaceDriftResolution resolution,
  }) {
    resolvedSkillDrifts.add((review: review, resolution: resolution));
    if (resolveSkillDriftTasks.isNotEmpty) {
      return resolveSkillDriftTasks.removeAt(0);
    }
    final next = resolveSkillDriftSnapshot;
    if (next != null) _commitSnapshot(next);
    if (resolveSkillDriftIntegrity case final status?) {
      publishIntegrity(skills: {review.skillId: status});
    }
    return completedWorkspaceTask(
      kind: WorkspaceOperationKind.resolveSkillDrift,
      value: WorkspaceMutationReceipt(
        snapshot: _current,
        affectedSkillIds: {review.skillId},
      ),
    );
  }

  Future<void> dispose() async {
    if (!_snapshots.isClosed) await _snapshots.close();
  }

  WorkspaceMutationReceipt _receipt(Set<String> slotKeys) =>
      WorkspaceMutationReceipt(
        snapshot: _current,
        affectedSkillIds: {
          for (final slotKey in slotKeys)
            if (_current.findSkillBySlotKey(slotKey) case final skill?)
              skill.id,
        },
      );

  String _slotKeyOf(WorkspaceSkillId skillId) =>
      _current.findSkillById(skillId)?.slotKey ??
      (skillId.value.startsWith('legacy:')
          ? skillId.value.substring('legacy:'.length)
          : skillId.value);

  void _replaceSkill(
    WorkspaceSkillId skillId,
    WorkspaceSkill Function(WorkspaceSkill skill) replace,
  ) {
    final nextSkills = [
      for (final skill in _current.skills)
        if (skill.id == skillId) replace(skill) else skill,
    ];
    _commitSnapshot(
      SkillsWorkspaceSnapshot(
        revision: _current.revision + 1,
        projectRoots: _current.projectRoots,
        skills: nextSkills,
        personalTags: _current.personalTags,
        integrity: _current.integrity,
      ),
    );
  }

  void _commitSnapshot(SkillsWorkspaceSnapshot snapshot) {
    _current = snapshot;
    if (!_snapshots.isClosed) _snapshots.add(snapshot);
  }
}

WorkspaceTask<T> completedWorkspaceTask<T>({
  required WorkspaceOperationKind kind,
  required T value,
}) => WorkspaceTask(
  current: _terminalProgress(kind, WorkspaceOperationPhase.succeeded),
  states: const Stream.empty(),
  completed: Future.value(WorkspaceCompleted(value: value)),
  cancel: () async {},
);

WorkspaceTask<T> failedWorkspaceTask<T>({
  required WorkspaceOperationKind kind,
  required WorkspaceException error,
}) => WorkspaceTask(
  current: _terminalProgress(kind, WorkspaceOperationPhase.failed),
  states: const Stream.empty(),
  completed: Future.value(WorkspaceFailed(failure: error)),
  cancel: () async {},
);

WorkspaceOperationProgress _terminalProgress(
  WorkspaceOperationKind kind,
  WorkspaceOperationPhase phase,
) => WorkspaceOperationProgress(
  operationId: 'fake-${kind.name}',
  kind: kind,
  phase: phase,
);
