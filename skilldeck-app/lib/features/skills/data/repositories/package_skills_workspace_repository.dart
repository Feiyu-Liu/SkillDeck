import 'dart:async';
import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:skills_manager/features/skills/data/repositories/skills_workspace_repository.dart';
import 'package:skills_manager/features/skills/models/external_skills.dart';
import 'package:skills_manager/features/skills/models/skill_document.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_workspace/skills_workspace.dart' as workspace;

/// Production adapter for the unified `skills_workspace` bounded context.
///
/// The adapter is intentionally unselected until the Runtime cutover. It maps
/// every package value into App-owned domain types and never exposes package
/// identities, persistence paths, or presentation concerns to callers.
final class PackageSkillsWorkspaceRepository
    implements SkillsWorkspaceRepository, SkillsUpdateCheckStore {
  PackageSkillsWorkspaceRepository({
    required workspace.SkillsRepository backend,
  }) : _backend = backend;

  factory PackageSkillsWorkspaceRepository.create({
    required workspace.SkillsRepositoryConfiguration configuration,
  }) => PackageSkillsWorkspaceRepository(
    backend: workspace.createSkillsRepository(configuration),
  );

  static final _personalTagColor = RegExp(r'^#[0-9A-Fa-f]{6}$');

  final workspace.SkillsRepository _backend;
  final Object _driftReviewOwner = Object();
  final StreamController<SkillsWorkspaceSnapshot> _snapshots =
      StreamController<SkillsWorkspaceSnapshot>.broadcast();
  StreamSubscription<workspace.RepositorySnapshot>? _subscription;
  workspace.RepositorySnapshot? _lastPublishedSource;
  SkillsWorkspaceSnapshot? _current;
  bool _closed = false;

  @override
  Future<WorkspaceUpdateCacheSnapshot> readUpdateCache() async {
    final cache = await _backend.updateCheckStore.read();
    return WorkspaceUpdateCacheSnapshot(
      records: [
        for (final record in cache.records)
          WorkspaceUpdateCacheRecord(
            skillId: WorkspaceSkillId(record.managedSkillId.value),
            basisFingerprint: record.basisFingerprint,
            report: _updateReportFromCache(record),
            checkedAt: record.checkedAt,
          ),
      ],
      lastFullSweepAt: cache.lastFullSweepAt,
    );
  }

  @override
  Future<void> upsertUpdateCache(WorkspaceUpdateCacheRecord record) =>
      _backend.updateCheckStore.upsert(
        workspace.UpdateCheckRecord(
          managedSkillId: _backendId(record.skillId),
          basisFingerprint: record.basisFingerprint,
          status: _packageUpdateStatus(record.report.status),
          currentContentHash: record.report.currentContentHash,
          availableContentHash: record.report.availableContentHash,
          resolvedSourceRevision: record.report.resolvedSourceRevision,
          checkedAt: record.checkedAt,
        ),
      );

  @override
  Future<void> removeUpdateCache(WorkspaceSkillId skillId) =>
      _backend.updateCheckStore.remove(_backendId(skillId));

  @override
  Future<void> writeLastFullUpdateSweepAt(DateTime value) =>
      _backend.updateCheckStore.writeLastFullSweepAt(value);

  @override
  SkillsWorkspaceSnapshot? get current => _current;

  @override
  WorkspaceTask<WorkspaceSkillDriftReview> inspectSkillDrift(
    WorkspaceSkillId skillId,
  ) => _task(
    _backend.inspectSkillDrift(
      workspace.InspectSkillDriftRequest(managedSkillId: _backendId(skillId)),
    ),
    WorkspaceOperationKind.inspectSkillDrift,
    (review) => _PackageWorkspaceSkillDriftReview(review, _driftReviewOwner),
  );

  @override
  WorkspaceTask<WorkspaceSkillDriftExport> exportSkillDriftArtifact({
    required WorkspaceSkillDriftReview review,
    required String artifactId,
    required String destinationDirectory,
  }) {
    if (review is! _PackageWorkspaceSkillDriftReview ||
        !identical(review.owner, _driftReviewOwner)) {
      return _failedTask(
        WorkspaceOperationKind.exportSkillDriftArtifact,
        WorkspaceErrorCode.staleDriftReview,
        context: const {'reason': 'foreignReview'},
      );
    }
    return _task(
      _backend.exportSkillDriftArtifact(
        workspace.ExportSkillDriftArtifactRequest(
          review: review.backendReview,
          artifactId: artifactId,
          destinationDirectory: destinationDirectory,
        ),
      ),
      WorkspaceOperationKind.exportSkillDriftArtifact,
      (export) => WorkspaceSkillDriftExport(exportedPath: export.exportedPath),
    );
  }

  @override
  WorkspaceTask<WorkspaceMutationReceipt> resolveSkillDrift({
    required WorkspaceSkillDriftReview review,
    required WorkspaceDriftResolution resolution,
  }) {
    if (review is! _PackageWorkspaceSkillDriftReview ||
        !identical(review.owner, _driftReviewOwner)) {
      return _failedTask(
        WorkspaceOperationKind.resolveSkillDrift,
        WorkspaceErrorCode.staleDriftReview,
        context: const {'reason': 'foreignReview'},
      );
    }
    return _mutationTask(
      _backend.resolveSkillDrift(
        workspace.ResolveSkillDriftRequest(
          review: review.backendReview,
          resolution: switch (resolution) {
            WorkspaceKeepExternalSkillDrift(:final artifactId) =>
              workspace.KeepExternalSkillDrift(artifactId),
            WorkspaceRestoreManagedSkillDrift() =>
              const workspace.RestoreManagedSkillDrift(),
          },
        ),
      ),
      WorkspaceOperationKind.resolveSkillDrift,
    );
  }

  @override
  Stream<SkillsWorkspaceSnapshot> get snapshots => _snapshots.stream;

  @override
  Future<WorkspaceCompletion<SkillsWorkspaceSnapshot>> open() {
    _requireNotClosed();
    final opened = _current;
    if (opened != null) {
      return _completedTask(WorkspaceOperationKind.open, opened).completed;
    }
    _subscription ??= _backend.snapshots.listen(_publish);
    return _task(
      _backend.open(),
      WorkspaceOperationKind.open,
      _publish,
    ).completed;
  }

  @override
  Future<WorkspaceCompletion<SkillsWorkspaceSnapshot>> refresh() => _task(
    _backend.refresh(),
    WorkspaceOperationKind.refresh,
    _publish,
  ).completed;

  @override
  WorkspaceTask<WorkspaceValidationReport> validateWorkspace({
    Set<WorkspaceSkillId>? skillIds,
  }) => _task(
    _backend.validateWorkspace(
      workspace.ValidateWorkspaceRequest(
        managedSkillIds: skillIds == null
            ? null
            : {for (final id in skillIds) _backendId(id)},
      ),
    ),
    WorkspaceOperationKind.validateWorkspace,
    (report) => WorkspaceValidationReport(
      checkedSkillCount: report.checkedSkillCount,
      repairedArtifactCount: report.repairedArtifactCount,
      healthySkillCount: report.healthySkillCount,
      repairedSkillIds: [
        for (final id in report.repairedSkillIds) WorkspaceSkillId(id.value),
      ],
      driftedSkillIds: [
        for (final id in report.driftedSkillIds) WorkspaceSkillId(id.value),
      ],
      failedSkillIds: [
        for (final id in report.failedSkillIds) WorkspaceSkillId(id.value),
      ],
    ),
  );

  @override
  WorkspaceTask<SkillsWorkspaceSnapshot> resumeFinalizationRecovery() => _task(
    _backend.resumeFinalizationRecovery(),
    WorkspaceOperationKind.resumeFinalizationRecovery,
    _publish,
  );

  @override
  Future<WorkspaceCompletion<List<SkillDocumentEntry>>> listSkillDocuments(
    WorkspaceSkillId skillId,
  ) {
    if (_current?.findSkillById(skillId) == null) {
      return _failedTask<List<SkillDocumentEntry>>(
        WorkspaceOperationKind.readDocument,
        WorkspaceErrorCode.skillNotFound,
        context: {'skillId': skillId.value},
      ).completed;
    }
    return _task<
          workspace.EffectiveSkillFileManifest,
          List<SkillDocumentEntry>
        >(
          _backend.listEffectiveFiles(
            workspace.ListEffectiveFilesRequest(
              managedSkillId: _backendId(skillId),
            ),
          ),
          WorkspaceOperationKind.readDocument,
          (manifest) {
            final markdown = manifest.files
                .where(
                  (entry) => entry.relativePath.toLowerCase().endsWith('.md'),
                )
                .map(
                  (entry) => SkillDocumentEntry(
                    relativePath: entry.relativePath,
                    name: p.basename(entry.relativePath),
                    contentHash: manifest.contentHash,
                  ),
                )
                .toList();
            markdown.sort((left, right) {
              final leftPrimary = left.relativePath.toLowerCase() == 'skill.md';
              final rightPrimary =
                  right.relativePath.toLowerCase() == 'skill.md';
              if (leftPrimary != rightPrimary) return leftPrimary ? -1 : 1;
              return left.relativePath.toLowerCase().compareTo(
                right.relativePath.toLowerCase(),
              );
            });
            return List.unmodifiable(markdown);
          },
        )
        .completed;
  }

  @override
  Future<WorkspaceCompletion<String>> readSkillDocument(
    WorkspaceSkillId skillId,
    String relativePath, {
    required String expectedContentHash,
  }) {
    final skill = _current?.findSkillById(skillId);
    if (skill == null) {
      return _failedTask<String>(
        WorkspaceOperationKind.readDocument,
        WorkspaceErrorCode.skillNotFound,
        context: {'skillId': skillId.value},
      ).completed;
    }
    final task =
        _task<
          workspace.EffectiveSkillFileContent,
          workspace.EffectiveSkillFileContent
        >(
          _backend.readEffectiveFile(
            workspace.ReadEffectiveFileRequest(
              managedSkillId: _backendId(skill.id),
              expectedContentHash: expectedContentHash,
              relativePath: relativePath,
            ),
          ),
          WorkspaceOperationKind.readDocument,
          (value) => value,
        );
    return task.completed.then((completion) {
      return switch (completion) {
        WorkspaceCompleted(:final value, :final warnings) => _decodeDocument(
          value.bytes,
          relativePath,
          warnings,
        ),
        WorkspaceFailed(:final failure, :final warnings) => WorkspaceFailed(
          failure: failure,
          warnings: warnings,
        ),
        WorkspaceCommittedPending(
          :final operationId,
          :final committedRevision,
          :final warnings,
        ) =>
          WorkspaceCommittedPending(
            operationId: operationId,
            committedRevision: committedRevision,
            warnings: warnings,
          ),
      };
    });
  }

  @override
  WorkspaceTask<WorkspaceSourceInspection> inspectSource(
    SkillSourceInput source,
  ) {
    final backendSource = _source(source);
    if (backendSource == null) {
      return _failedTask(
        WorkspaceOperationKind.inspectSource,
        WorkspaceErrorCode.invalidSource,
      );
    }
    return _task(
      _backend.inspectSource(
        workspace.InspectSourceRequest(source: backendSource),
      ),
      WorkspaceOperationKind.inspectSource,
      (inspection) {
        final canonical = _sourceProvenance(inspection.source);
        return WorkspaceSourceInspection(
          source: SkillSourceInput(
            kind: canonical.kind,
            locator: canonical.locator,
            ref: canonical.ref,
            repositorySubpath: canonical.repositorySubpath,
            skillPath: canonical.skillPath,
          ),
          candidates: [
            for (final candidate in inspection.candidates)
              WorkspaceSourceCandidate(
                declaredName: candidate.declaredName,
                description: candidate.description,
                slotKey: candidate.slotKey,
                skillPath: candidate.skillPath,
                contentHash: candidate.contentHash,
                fileCount: candidate.fileCount,
                byteSize: candidate.byteSize,
              ),
          ],
        );
      },
    );
  }

  @override
  Future<WorkspaceGitEnvironmentStatus> probeGitEnvironment() async {
    final report = await _backend.probeGitEnvironment();
    return switch (report.status) {
      workspace.GitEnvironmentStatus.available =>
        WorkspaceGitEnvironmentStatus.available,
      workspace.GitEnvironmentStatus.notInstalled =>
        WorkspaceGitEnvironmentStatus.notInstalled,
      workspace.GitEnvironmentStatus.developerToolsRequired =>
        WorkspaceGitEnvironmentStatus.developerToolsRequired,
      workspace.GitEnvironmentStatus.developerToolsInstalling =>
        WorkspaceGitEnvironmentStatus.developerToolsInstalling,
      workspace.GitEnvironmentStatus.probeFailed =>
        WorkspaceGitEnvironmentStatus.probeFailed,
    };
  }

  @override
  WorkspaceTask<List<WorkspaceAgentInfo>> inspectAgents() => _task(
    _backend.inspectAgents(),
    WorkspaceOperationKind.inspectAgents,
    (agents) => [
      for (final agent in agents)
        WorkspaceAgentInfo(
          id: agent.id,
          displayName: agent.displayName,
          isBuiltIn: agent.isBuiltIn,
          supportedScopes: {
            for (final scope in agent.supportedScopes)
              scope == workspace.ActivationScope.global
                  ? WorkspaceScope.global
                  : WorkspaceScope.project,
          },
          detectedGlobally: agent.detectedGlobally,
          detectedProjectRootIds: agent.detectedProjectRootIds,
        ),
    ],
  );

  @override
  WorkspaceTask<List<WorkspaceActivationTarget>> inspectActivationTargets({
    required WorkspaceScope scope,
    String? projectRootId,
  }) => _task(
    _backend.inspectActivationTargets(
      workspace.InspectActivationTargetsRequest(
        scope: _backendScope(scope),
        projectRootId: projectRootId,
      ),
    ),
    WorkspaceOperationKind.inspectActivationTargets,
    (targets) => [for (final target in targets) _activationTarget(target)],
  );

  @override
  WorkspaceTask<WorkspaceAgentRootOwnershipAudit> inspectAgentRootOwnership() =>
      _task(
        _backend.inspectAgentRootOwnership(
          const workspace.InspectAgentRootOwnershipRequest(),
        ),
        WorkspaceOperationKind.inspectAgentRootOwnership,
        (audit) => WorkspaceAgentRootOwnershipAudit(
          supported: audit.supported,
          currentUserId: audit.currentUserId,
          examinedRootCount: audit.examinedRootCount,
          issues: [
            for (final issue in audit.issues)
              WorkspaceAgentRootOwnershipIssue(
                rootPath: issue.rootPath,
                agentIds: issue.agentIds,
                customAgentIds: issue.customAgentIds,
                roles: {
                  for (final role in issue.roles)
                    switch (role) {
                      workspace.AgentSkillRootRole.canonicalActivation =>
                        WorkspaceAgentSkillRootRole.canonicalActivation,
                      workspace.AgentSkillRootRole.compatibilityDiscovery =>
                        WorkspaceAgentSkillRootRole.compatibilityDiscovery,
                    },
                },
                reason: switch (issue.reason) {
                  workspace.AgentRootOwnershipIssueReason.ownerMismatch =>
                    WorkspaceAgentRootOwnershipIssueReason.ownerMismatch,
                  workspace.AgentRootOwnershipIssueReason.outsideUserHome =>
                    WorkspaceAgentRootOwnershipIssueReason.outsideUserHome,
                  workspace.AgentRootOwnershipIssueReason.notDirectory =>
                    WorkspaceAgentRootOwnershipIssueReason.notDirectory,
                  workspace.AgentRootOwnershipIssueReason.inspectionFailed =>
                    WorkspaceAgentRootOwnershipIssueReason.inspectionFailed,
                },
                repairable: issue.repairable,
              ),
          ],
        ),
      );

  @override
  WorkspaceTask<ExternalSkillsDiscovery> discoverExternalSkills() => _task(
    _backend.discoverExternalSkills(
      const workspace.DiscoverExternalSkillsRequest(
        scanAllKnownLocations: true,
      ),
    ),
    WorkspaceOperationKind.discoverExternalSkills,
    (discovery) => ExternalSkillsDiscovery(
      candidates: [
        for (final candidate in discovery.candidates)
          ExternalSkillCandidate(
            slotKey: candidate.slotKey,
            declaredName: candidate.declaredName,
            description: candidate.description,
            contentHash: candidate.contentHash,
            locations: candidate.locations,
            agentIds: candidate.agentIds,
            destinationLocations: candidate.destinationLocations,
          ),
      ],
      conflicts: [
        for (final conflict in discovery.conflicts)
          ExternalSkillConflict(
            slotKey: conflict.slotKey,
            contentHashByLocation: conflict.contentHashByLocation,
            destinationLocations: conflict.destinationLocations,
            agentIdsByLocation: conflict.agentIdsByLocation,
          ),
      ],
    ),
  );

  @override
  WorkspaceTask<WorkspaceInstallAttempt> install(
    WorkspaceInstallRequest request,
  ) {
    final backendSource = _source(request.source);
    if (backendSource == null) {
      return _failedTask(
        WorkspaceOperationKind.install,
        WorkspaceErrorCode.invalidSource,
      );
    }
    return _task(
      _backend.install(
        workspace.InstallRequest(
          source: backendSource,
          selectedSkillNames: request.skillNames,
          activationSelection: request.storeOnly
              ? const workspace.ActivationSelection.none()
              : _activationSelection(
                  scope: request.scope,
                  projectRootId: request.projectRootId,
                  agentIds: request.agentIds,
                ),
          activationMode: _requestedMode(
            request.activationMethod,
            scope: request.scope,
          ),
          lockWaitPolicy: _lockWait,
        ),
      ),
      WorkspaceOperationKind.install,
      (attempt) => switch (attempt) {
        workspace.InstallCompleted(:final report) => WorkspaceInstallCompleted(
          _receipt(report),
        ),
        workspace.InstallTakeoverRequired(:final draft) =>
          WorkspaceInstallTakeoverRequired(
            _PackageWorkspaceInstallTakeoverDraft(draft),
          ),
      },
    );
  }

  @override
  WorkspaceTask<WorkspaceMutationReceipt> confirmInstallTakeover(
    WorkspaceInstallTakeoverDraft draft,
  ) {
    if (draft is! _PackageWorkspaceInstallTakeoverDraft) {
      return _failedTask(
        WorkspaceOperationKind.confirmInstallTakeover,
        WorkspaceErrorCode.operationFailed,
        context: const {'reason': 'invalidInstallTakeoverDraft'},
      );
    }
    return _mutationTask(
      _backend.confirmInstallTakeover(
        workspace.ConfirmInstallTakeoverRequest(
          draft: draft.backendDraft,
          lockWaitPolicy: _lockWait,
        ),
      ),
      WorkspaceOperationKind.confirmInstallTakeover,
    );
  }

  @override
  WorkspaceTask<WorkspaceMutationReceipt> adopt(
    ExternalSkillAdoptionRequest request,
  ) => _mutationTask(
    _backend.adopt(
      workspace.AdoptRequest(
        selection: workspace.ExternalAdoptionSelection(
          slotKey: request.slotKey,
          reviewedContentHashByLocation: request.reviewedContentHashByLocation,
          authoritativeLocation: request.authoritativeLocation,
        ),
        activationMode: _requestedMode(request.activationMethod, scope: null),
        lockWaitPolicy: _lockWait,
      ),
    ),
    WorkspaceOperationKind.adopt,
  );

  @override
  WorkspaceTask<WorkspaceMutationReceipt> replaceSource({
    required WorkspaceSkillId skillId,
    required SkillSourceInput source,
    required int expectedRevision,
  }) {
    final backendSource = _source(source);
    if (backendSource == null) {
      return _failedTask(
        WorkspaceOperationKind.replaceSource,
        WorkspaceErrorCode.invalidSource,
      );
    }
    return _mutationTask(
      _backend.replaceSource(
        workspace.ReplaceSourceRequest(
          managedSkillId: _backendId(skillId),
          source: backendSource,
          intent: workspace.DestructiveIntent(
            reviewedRevision: workspace.RepositoryRevision(expectedRevision),
          ),
          lockWaitPolicy: _lockWait,
        ),
      ),
      WorkspaceOperationKind.replaceSource,
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
  }) => _task(
    _backend.activate(
      workspace.ActivateRequest(
        managedSkillIds: _backendIds(skillIds),
        selection: _activationSelection(
          scope: scope,
          projectRootId: projectRootId,
          agentIds: agentIds,
        ),
        mode: _requestedMode(activationMethod, scope: scope),
        lockWaitPolicy: _lockWait,
      ),
    ),
    WorkspaceOperationKind.activate,
    (attempt) => switch (attempt) {
      workspace.ActivationCompleted(:final report) =>
        WorkspaceActivationCompleted(_receipt(report)),
      workspace.ActivationTakeoverRequired(:final draft) =>
        WorkspaceActivationTakeoverRequired(
          _PackageWorkspaceActivationTakeoverDraft(
            draft,
            slotKeyOf: _slotKeyOf,
          ),
        ),
    },
  );

  @override
  WorkspaceTask<WorkspaceMutationReceipt> confirmActivationTakeover(
    WorkspaceActivationTakeoverDraft draft,
  ) {
    if (draft is! _PackageWorkspaceActivationTakeoverDraft) {
      return _failedTask(
        WorkspaceOperationKind.confirmActivationTakeover,
        WorkspaceErrorCode.operationFailed,
        context: const {'reason': 'invalidActivationTakeoverDraft'},
      );
    }
    return _mutationTask(
      _backend.confirmActivationTakeover(
        workspace.ConfirmActivationTakeoverRequest(
          draft: draft.backendDraft,
          lockWaitPolicy: _lockWait,
        ),
      ),
      WorkspaceOperationKind.confirmActivationTakeover,
    );
  }

  @override
  WorkspaceTask<WorkspaceMutationReceipt> deactivate({
    required Set<WorkspaceSkillId> skillIds,
    Set<String>? locations,
  }) => _mutationTask(
    _backend.deactivate(
      workspace.DeactivateRequest(
        managedSkillIds: _backendIds(skillIds),
        locations: locations,
        lockWaitPolicy: _lockWait,
      ),
    ),
    WorkspaceOperationKind.deactivate,
  );

  @override
  WorkspaceTask<WorkspaceMutationReceipt> remove({
    required Set<WorkspaceSkillId> skillIds,
    required int expectedRevision,
  }) => _mutationTask(
    _backend.remove(
      workspace.RemoveRequest(
        managedSkillIds: _backendIds(skillIds),
        intent: workspace.DestructiveIntent(
          reviewedRevision: workspace.RepositoryRevision(expectedRevision),
        ),
        lockWaitPolicy: _lockWait,
      ),
    ),
    WorkspaceOperationKind.remove,
  );

  @override
  WorkspaceTask<List<WorkspaceUpdateReport>> checkUpdates({
    Set<WorkspaceSkillId>? skillIds,
  }) => _task(
    _backend.checkUpdates(
      workspace.CheckUpdatesRequest(
        managedSkillIds: skillIds == null ? null : _backendIds(skillIds),
      ),
    ),
    WorkspaceOperationKind.checkUpdates,
    (reports) => [for (final report in reports) _updateReport(report)],
  );

  @override
  WorkspaceTask<WorkspaceMutationReceipt> update({
    Set<WorkspaceSkillId>? skillIds,
  }) {
    final current = _current;
    if (skillIds == null && current == null) {
      return _failedTask(
        WorkspaceOperationKind.update,
        WorkspaceErrorCode.repositoryNotOpen,
      );
    }
    final ids = skillIds == null
        ? {for (final skill in current!.skills) _backendId(skill.id)}
        : _backendIds(skillIds);
    if (ids.isEmpty) {
      if (current == null) {
        return _failedTask(
          WorkspaceOperationKind.update,
          WorkspaceErrorCode.repositoryNotOpen,
        );
      }
      return _completedTask(
        WorkspaceOperationKind.update,
        WorkspaceMutationReceipt(snapshot: current, affectedSkillIds: const {}),
      );
    }
    return _mutationTask(
      _backend.update(
        workspace.UpdateRequest(
          managedSkillIds: ids,
          lockWaitPolicy: _lockWait,
        ),
      ),
      WorkspaceOperationKind.update,
    );
  }

  @override
  WorkspaceTask<WorkspaceMutationReceipt> registerProjectRoot({
    required String path,
    String? id,
  }) => _mutationTask(
    _backend.registerProjectRoot(
      workspace.RegisterProjectRootRequest(path: p.normalize(path), id: id),
    ),
    WorkspaceOperationKind.registerProjectRoot,
  );

  @override
  WorkspaceTask<WorkspaceMutationReceipt> unregisterProjectRoot(String id) =>
      _mutationTask(
        _backend.unregisterProjectRoot(
          workspace.UnregisterProjectRootRequest(id: id),
        ),
        WorkspaceOperationKind.unregisterProjectRoot,
      );

  @override
  WorkspaceTask<SkillsWorkspaceSnapshot> reconfigureAgentCatalog(
    List<WorkspaceAgentDefinition> agents,
  ) => _task(
    _backend.reconfigureAgentCatalog(
      workspace.ReconfigureAgentCatalogRequest(
        agents: [for (final agent in agents) _agentDefinition(agent)],
      ),
    ),
    WorkspaceOperationKind.reconfigureAgentCatalog,
    _publish,
  );

  @override
  WorkspaceTask<SkillsWorkspaceSnapshot> setFavorite({
    required WorkspaceSkillId skillId,
    required bool isFavorite,
  }) => _task(
    _backend.setFavorite(
      workspace.SetFavoriteRequest(
        managedSkillId: _backendId(skillId),
        isFavorite: isFavorite,
      ),
    ),
    WorkspaceOperationKind.setFavorite,
    _publish,
  );

  @override
  WorkspaceTask<SkillsWorkspaceSnapshot> saveNote({
    required WorkspaceSkillId skillId,
    required String note,
  }) => note.trim().isEmpty
      ? deleteNote(skillId)
      : _task(
          _backend.saveNote(
            workspace.SaveNoteRequest(
              managedSkillId: _backendId(skillId),
              text: note,
            ),
          ),
          WorkspaceOperationKind.saveNote,
          _publish,
        );

  @override
  WorkspaceTask<SkillsWorkspaceSnapshot> deleteNote(WorkspaceSkillId skillId) =>
      _task(
        _backend.deleteNote(
          workspace.DeleteNoteRequest(managedSkillId: _backendId(skillId)),
        ),
        WorkspaceOperationKind.deleteNote,
        _publish,
      );

  @override
  WorkspaceTask<WorkspacePersonalTag> createPersonalTag({
    required String name,
    String? color,
  }) {
    const kind = WorkspaceOperationKind.createPersonalTag;
    final invalid = _personalTagInputFailure(kind, name: name, color: color);
    if (invalid != null) return invalid;
    return _task(
      _backend.createPersonalTag(
        workspace.CreatePersonalTagRequest(name: name, color: color),
      ),
      kind,
      _publishedPersonalTag,
    );
  }

  @override
  WorkspaceTask<WorkspacePersonalTag> updatePersonalTag({
    required String tagId,
    required String name,
    String? color,
  }) {
    const kind = WorkspaceOperationKind.updatePersonalTag;
    final invalid = _personalTagInputFailure(kind, name: name, color: color);
    if (invalid != null) return invalid;
    return _task(
      _backend.updatePersonalTag(
        workspace.UpdatePersonalTagRequest(
          tagId: tagId,
          name: name,
          color: color,
        ),
      ),
      kind,
      _publishedPersonalTag,
    );
  }

  @override
  WorkspaceTask<SkillsWorkspaceSnapshot> deletePersonalTag(String tagId) =>
      _task(
        _backend.deletePersonalTag(
          workspace.DeletePersonalTagRequest(tagId: tagId),
        ),
        WorkspaceOperationKind.deletePersonalTag,
        _publish,
      );

  @override
  WorkspaceTask<SkillsWorkspaceSnapshot> assignPersonalTag({
    required WorkspaceSkillId skillId,
    required String tagId,
  }) => _task(
    _backend.assignPersonalTag(
      workspace.AssignPersonalTagRequest(
        managedSkillId: _backendId(skillId),
        tagId: tagId,
      ),
    ),
    WorkspaceOperationKind.assignPersonalTag,
    _publish,
  );

  @override
  WorkspaceTask<SkillsWorkspaceSnapshot> unassignPersonalTag({
    required WorkspaceSkillId skillId,
    required String tagId,
  }) => _task(
    _backend.unassignPersonalTag(
      workspace.UnassignPersonalTagRequest(
        managedSkillId: _backendId(skillId),
        tagId: tagId,
      ),
    ),
    WorkspaceOperationKind.unassignPersonalTag,
    _publish,
  );

  // Request constructors throw on blank names and the engine reports a
  // malformed color only as a generic failure, so reject both up front.
  WorkspaceTask<WorkspacePersonalTag>? _personalTagInputFailure(
    WorkspaceOperationKind kind, {
    required String name,
    required String? color,
  }) {
    if (name.trim().isEmpty || name.contains('\u0000')) {
      return _failedTask(
        kind,
        WorkspaceErrorCode.operationFailed,
        context: const {'reason': 'invalidPersonalTagName'},
      );
    }
    if (color != null && !_personalTagColor.hasMatch(color)) {
      return _failedTask(
        kind,
        WorkspaceErrorCode.operationFailed,
        context: const {'reason': 'invalidPersonalTagColor'},
      );
    }
    return null;
  }

  // Tag mutations return the tag rather than a snapshot; publish the
  // backend's current snapshot so readers see the change immediately.
  WorkspacePersonalTag _publishedPersonalTag(workspace.PersonalTag tag) {
    if (_backend.isOpen) _publish(_backend.snapshot);
    return _personalTag(tag);
  }

  WorkspacePersonalTag _personalTag(workspace.PersonalTag tag) =>
      WorkspacePersonalTag(
        id: tag.id,
        name: tag.name,
        color: tag.color,
        createdAt: tag.createdAt,
        updatedAt: tag.updatedAt,
      );

  @override
  WorkspaceTask<SkillsWorkspaceSnapshot> abandonUpdateCandidate(
    WorkspaceSkillId skillId,
  ) => _task(
    _backend.abandonUpdateCandidate(
      workspace.AbandonUpdateCandidateRequest(
        managedSkillId: _backendId(skillId),
      ),
    ),
    WorkspaceOperationKind.abandonUpdateCandidate,
    _publish,
  );

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _subscription?.cancel();
    _subscription = null;
    final completion = await _task<void, void>(
      _backend.close(),
      WorkspaceOperationKind.close,
      (_) {},
    ).completed;
    await _snapshots.close();
    switch (completion) {
      case WorkspaceCompleted():
        return;
      case WorkspaceFailed(:final failure):
        throw failure;
      case WorkspaceCommittedPending(:final operationId):
        throw StateError(
          'Close operation $operationId committed but finalization is pending.',
        );
    }
  }

  WorkspaceTask<WorkspaceMutationReceipt> _mutationTask(
    workspace.SkillsOperation<workspace.MutationReport> operation,
    WorkspaceOperationKind kind,
  ) => _task(operation, kind, _receipt);

  WorkspaceMutationReceipt _receipt(workspace.MutationReport report) =>
      WorkspaceMutationReceipt(
        snapshot: _publish(report.snapshot),
        affectedSkillIds: {
          for (final id in report.affectedSkillIds) WorkspaceSkillId(id.value),
        },
      );

  WorkspaceTask<R> _task<T, R>(
    workspace.SkillsOperation<T> operation,
    WorkspaceOperationKind kind,
    R Function(T value) map,
  ) => WorkspaceTask<R>(
    current: WorkspaceOperationProgress(
      operationId: operation.operationId.value,
      kind: kind,
      phase: WorkspaceOperationPhase.queued,
    ),
    states: operation.progress.map((value) => _progress(value, kind)),
    completed: operation.completed.then(
      (result) => result.fold<WorkspaceCompletion<R>>(
        onSuccess: (success) => WorkspaceCompleted(
          value: map(success.value),
          warnings: success.warnings.map(_warning).toList(),
        ),
        onFailure: (failure) => WorkspaceFailed(
          failure: _failure(failure, kind),
          warnings: failure.warnings.map(_warning).toList(),
        ),
        onCommittedFinalizationPending: (pending) => WorkspaceCommittedPending(
          operationId: pending.operationId.value,
          committedRevision: pending.committedRepositoryRevision.value,
          warnings: pending.warnings.map(_warning).toList(),
        ),
      ),
    ),
    cancel: operation.cancel,
  );

  WorkspaceTask<T> _failedTask<T>(
    WorkspaceOperationKind kind,
    WorkspaceErrorCode code, {
    Map<String, Object?> context = const {},
  }) => WorkspaceTask(
    current: WorkspaceOperationProgress(
      operationId: 'app-precondition',
      kind: kind,
      phase: WorkspaceOperationPhase.failed,
    ),
    states: const Stream.empty(),
    completed: Future.value(
      WorkspaceFailed(
        failure: WorkspaceFailure(
          code: code,
          operation: kind,
          context: context,
        ),
      ),
    ),
    cancel: () async {},
  );

  WorkspaceTask<T> _completedTask<T>(WorkspaceOperationKind kind, T value) =>
      WorkspaceTask(
        current: WorkspaceOperationProgress(
          operationId: 'app-noop',
          kind: kind,
          phase: WorkspaceOperationPhase.succeeded,
        ),
        states: const Stream.empty(),
        completed: Future.value(WorkspaceCompleted(value: value)),
        cancel: () async {},
      );

  WorkspaceCompletion<String> _decodeDocument(
    List<int> bytes,
    String relativePath,
    List<WorkspaceWarning> warnings,
  ) {
    try {
      return WorkspaceCompleted(
        value: utf8.decode(bytes, allowMalformed: false),
        warnings: warnings,
      );
    } on FormatException catch (error) {
      return WorkspaceFailed(
        failure: WorkspaceFailure(
          code: WorkspaceErrorCode.documentUnavailable,
          operation: WorkspaceOperationKind.readDocument,
          context: {'relativePath': relativePath},
          diagnostic: error.message,
          warnings: warnings,
        ),
        warnings: warnings,
      );
    }
  }

  WorkspaceOperationProgress _progress(
    workspace.OperationProgress source,
    WorkspaceOperationKind kind,
  ) => WorkspaceOperationProgress(
    operationId: source.operationId.value,
    kind: kind,
    phase: switch (source.phase) {
      workspace.OperationProgressPhase.queued => WorkspaceOperationPhase.queued,
      workspace.OperationProgressPhase.inspecting =>
        WorkspaceOperationPhase.inspecting,
      workspace.OperationProgressPhase.preparing =>
        WorkspaceOperationPhase.preparing,
      workspace.OperationProgressPhase.applying =>
        WorkspaceOperationPhase.applying,
      workspace.OperationProgressPhase.committing =>
        WorkspaceOperationPhase.committing,
      workspace.OperationProgressPhase.finalizing =>
        WorkspaceOperationPhase.finalizing,
    },
    currentItem: source.currentItem,
    completed: source.completed,
    total: source.total,
  );

  SkillsWorkspaceSnapshot _publish(workspace.RepositorySnapshot source) {
    // The backend assigns snapshot before queuing stream events. Its current
    // value wins over queued events and captured operation reports, so stale
    // same-revision integrity cannot overwrite a later validation result.
    if (_backend.isOpen) {
      final latest = _backend.snapshot;
      if (latest.revision.value >= source.revision.value) source = latest;
    }
    final current = _current;
    if (current != null) {
      if (current.revision > source.revision.value ||
          identical(_lastPublishedSource, source)) {
        return current;
      }
    }
    _lastPublishedSource = source;
    final mapped = _snapshot(source);
    _current = mapped;
    if (!_snapshots.isClosed) _snapshots.add(mapped);
    return mapped;
  }

  SkillsWorkspaceSnapshot _snapshot(workspace.RepositorySnapshot source) {
    final integrityById = {
      for (final entry in source.integrity.skills)
        entry.managedSkillId: entry.status,
    };
    return SkillsWorkspaceSnapshot(
      revision: source.revision.value,
      projectRoots: [
        for (final root in source.projectRoots)
          SkillProjectRoot(id: root.id, path: root.path),
      ],
      personalTags: [for (final tag in source.personalTags) _personalTag(tag)],
      integrity: switch (source.integrity.status) {
        workspace.WorkspaceIntegrityStatus.healthy =>
          WorkspaceIntegrityStatus.healthy,
        workspace.WorkspaceIntegrityStatus.recovered =>
          WorkspaceIntegrityStatus.recovered,
        workspace.WorkspaceIntegrityStatus.corrupt =>
          WorkspaceIntegrityStatus.corrupt,
      },
      skills: [
        for (final skill in source.managedSkills)
          _skill(skill, integrityById[skill.id]),
      ],
    );
  }

  WorkspaceSkill _skill(
    workspace.ManagedSkill source,
    workspace.SkillIntegrityStatus? integrity,
  ) => WorkspaceSkill(
    id: WorkspaceSkillId(source.id.value),
    createdAt: source.createdAt,
    slotKey: source.slotKey,
    declaredName: source.declaredName,
    displayName: source.displayName,
    description: source.description,
    source: _sourceProvenance(source.source),
    currentRevision: SkillRevision(
      contentHash: source.currentRevision.contentHash,
      fileCount: source.currentRevision.fileCount,
      byteSize: source.currentRevision.byteSize,
      acquiredAt: source.currentRevision.publishedAt,
      resolvedSourceRevision: source.currentRevision.resolvedSourceRevision,
    ),
    activations: [for (final item in source.activations) _activation(item)],
    isFavorite: source.favorite.isFavorite,
    note: source.note?.text,
    personalTagIds: source.personalTagIds,
    integrity: switch (integrity ?? workspace.SkillIntegrityStatus.healthy) {
      workspace.SkillIntegrityStatus.healthy =>
        WorkspaceSkillIntegrityStatus.healthy,
      workspace.SkillIntegrityStatus.recovered =>
        WorkspaceSkillIntegrityStatus.recovered,
      workspace.SkillIntegrityStatus.unverified =>
        WorkspaceSkillIntegrityStatus.unverified,
      workspace.SkillIntegrityStatus.validating =>
        WorkspaceSkillIntegrityStatus.validating,
      workspace.SkillIntegrityStatus.driftPending =>
        WorkspaceSkillIntegrityStatus.driftPending,
      workspace.SkillIntegrityStatus.repairFailed =>
        WorkspaceSkillIntegrityStatus.repairFailed,
      workspace.SkillIntegrityStatus.revisionStoreCorrupt =>
        WorkspaceSkillIntegrityStatus.revisionStoreCorrupt,
    },
    draft: source.draft == null ? null : _draft(source.draft!),
    updateCandidate: source.updateCandidate == null
        ? null
        : _updateCandidate(source.updateCandidate!),
  );

  WorkspaceDraftSummary _draft(workspace.DraftSummary source) =>
      WorkspaceDraftSummary(
        purpose: switch (source.purpose) {
          workspace.DraftPurpose.customization =>
            WorkspaceDraftPurpose.customization,
          workspace.DraftPurpose.updateCandidateResolution =>
            WorkspaceDraftPurpose.updateCandidateResolution,
        },
        path: source.path,
        isDirty: source.isDirty,
        updatedAt: source.updatedAt,
      );

  WorkspaceUpdateCandidateSummary _updateCandidate(
    workspace.UpdateCandidateSummary source,
  ) => WorkspaceUpdateCandidateSummary(
    status: switch (source.status) {
      workspace.UpdateCandidateStatus.conflicted =>
        WorkspaceUpdateCandidateStatus.conflicted,
      workspace.UpdateCandidateStatus.validationFailed =>
        WorkspaceUpdateCandidateStatus.validationFailed,
    },
    conflictPaths: [for (final conflict in source.conflicts) conflict.path],
    validationCode: source.validationCode,
    createdAt: source.createdAt,
  );

  WorkspaceUpdateReport _updateReport(workspace.UpdateReport source) {
    return WorkspaceUpdateReport(
      skillId: WorkspaceSkillId(source.managedSkillId.value),
      status: switch (source.status) {
        workspace.UpdateStatus.current => WorkspaceUpdateStatus.current,
        workspace.UpdateStatus.updateAvailable =>
          WorkspaceUpdateStatus.updateAvailable,
        workspace.UpdateStatus.sourceUnavailable =>
          WorkspaceUpdateStatus.sourceUnavailable,
        workspace.UpdateStatus.updateUnsupported =>
          WorkspaceUpdateStatus.updateUnsupported,
        workspace.UpdateStatus.resolutionRequired =>
          WorkspaceUpdateStatus.resolutionRequired,
      },
      currentContentHash: source.currentContentHash,
      availableContentHash: source.availableContentHash,
      resolvedSourceRevision: source.resolvedSourceRevision,
      failureReason: _updateFailureReason(source.failureReason),
    );
  }

  WorkspaceUpdateReport _updateReportFromCache(
    workspace.UpdateCheckRecord source,
  ) => WorkspaceUpdateReport(
    skillId: WorkspaceSkillId(source.managedSkillId.value),
    status: switch (source.status) {
      workspace.UpdateStatus.current => WorkspaceUpdateStatus.current,
      workspace.UpdateStatus.updateAvailable =>
        WorkspaceUpdateStatus.updateAvailable,
      workspace.UpdateStatus.sourceUnavailable =>
        WorkspaceUpdateStatus.sourceUnavailable,
      workspace.UpdateStatus.updateUnsupported =>
        WorkspaceUpdateStatus.updateUnsupported,
      workspace.UpdateStatus.resolutionRequired =>
        WorkspaceUpdateStatus.resolutionRequired,
    },
    currentContentHash: source.currentContentHash,
    availableContentHash: source.availableContentHash,
    resolvedSourceRevision: source.resolvedSourceRevision,
  );

  workspace.UpdateStatus _packageUpdateStatus(WorkspaceUpdateStatus status) =>
      switch (status) {
        WorkspaceUpdateStatus.current => workspace.UpdateStatus.current,
        WorkspaceUpdateStatus.updateAvailable =>
          workspace.UpdateStatus.updateAvailable,
        WorkspaceUpdateStatus.sourceUnavailable =>
          workspace.UpdateStatus.sourceUnavailable,
        WorkspaceUpdateStatus.updateUnsupported =>
          workspace.UpdateStatus.updateUnsupported,
        WorkspaceUpdateStatus.resolutionRequired =>
          workspace.UpdateStatus.resolutionRequired,
      };

  WorkspaceUpdateCheckFailureReason? _updateFailureReason(
    workspace.UpdateCheckFailureReason? reason,
  ) => switch (reason) {
    null => null,
    workspace.UpdateCheckFailureReason.sourceUnavailable =>
      WorkspaceUpdateCheckFailureReason.sourceUnavailable,
    workspace.UpdateCheckFailureReason.authenticationRequired =>
      WorkspaceUpdateCheckFailureReason.authenticationRequired,
    workspace.UpdateCheckFailureReason.gitUnavailable =>
      WorkspaceUpdateCheckFailureReason.gitUnavailable,
    workspace.UpdateCheckFailureReason.developerToolsRequired =>
      WorkspaceUpdateCheckFailureReason.developerToolsRequired,
    workspace.UpdateCheckFailureReason.timedOut =>
      WorkspaceUpdateCheckFailureReason.timedOut,
    workspace.UpdateCheckFailureReason.gitFailed =>
      WorkspaceUpdateCheckFailureReason.gitFailed,
    workspace.UpdateCheckFailureReason.ioFailure =>
      WorkspaceUpdateCheckFailureReason.ioFailure,
  };

  WorkspaceFailure _failure<T>(
    workspace.SkillsFailure<T> source,
    WorkspaceOperationKind operation,
  ) => WorkspaceFailure(
    code: _errorCode(source.code),
    operation: operation,
    context: source.context,
    diagnostic: source.diagnostic,
    warnings: source.warnings.map(_warning).toList(),
  );

  WorkspaceWarning _warning(workspace.SkillsWarning source) => WorkspaceWarning(
    code: _warningCode(source.code),
    context: source.context,
  );

  Set<workspace.ManagedSkillId> _backendIds(Set<WorkspaceSkillId> skillIds) => {
    for (final skillId in skillIds) _backendId(skillId),
  };

  workspace.ManagedSkillId _backendId(WorkspaceSkillId id) =>
      workspace.ManagedSkillId(id.value);

  workspace.AgentDefinition _agentDefinition(
    WorkspaceAgentDefinition source,
  ) => workspace.AgentDefinition(
    id: source.id,
    displayName: source.displayName,
    platforms: {
      for (final entry in source.platforms.entries)
        _backendPlatform(entry.key): workspace.AgentPlatformDefinition(
          globalSkillsPath: entry.value.globalSkillsPath,
          projectSkillsPath: entry.value.projectSkillsPath,
          globalDiscoverySkillsPaths: entry.value.globalDiscoverySkillsPaths,
          projectDiscoverySkillsPaths: entry.value.projectDiscoverySkillsPaths,
          detectionPaths: [
            if (entry.value.globalSkillsPath case final path?)
              workspace.AgentDetectionPath.absolute(path),
            for (final path in entry.value.globalDiscoverySkillsPaths)
              workspace.AgentDetectionPath.absolute(path),
            if (entry.value.projectSkillsPath case final path?)
              workspace.AgentDetectionPath.projectRelative(path),
            for (final path in entry.value.projectDiscoverySkillsPaths)
              workspace.AgentDetectionPath.projectRelative(path),
          ],
        ),
    },
  );

  String _slotKeyOf(workspace.ManagedSkillId id) =>
      _current?.findSkillById(WorkspaceSkillId(id.value))?.slotKey ?? '';

  void _requireNotClosed() {
    if (_closed) throw StateError('Skills Workspace repository is closed.');
  }
}

workspace.DesktopPlatform _backendPlatform(WorkspaceDesktopPlatform source) =>
    switch (source) {
      WorkspaceDesktopPlatform.macos => workspace.DesktopPlatform.macos,
      WorkspaceDesktopPlatform.windows => workspace.DesktopPlatform.windows,
      WorkspaceDesktopPlatform.linux => workspace.DesktopPlatform.linux,
    };

final class _PackageWorkspaceActivationTakeoverDraft
    implements WorkspaceActivationTakeoverDraft {
  _PackageWorkspaceActivationTakeoverDraft(
    this.backendDraft, {
    required String Function(workspace.ManagedSkillId id) slotKeyOf,
  }) : targets = List.unmodifiable([
         for (final target in backendDraft.targets)
           WorkspaceOccupiedActivationTarget(
             slotKey: slotKeyOf(target.managedSkillId),
             location: target.location,
             targetPath: target.targetPath,
             agentIds: target.agentIds,
             kind: switch (target.kind) {
               workspace.ActivationTargetOccupancyKind.skillDirectory =>
                 WorkspaceActivationTargetOccupancyKind.skillDirectory,
               workspace.ActivationTargetOccupancyKind.skillSymbolicLink =>
                 WorkspaceActivationTargetOccupancyKind.skillSymbolicLink,
               workspace.ActivationTargetOccupancyKind.file =>
                 WorkspaceActivationTargetOccupancyKind.file,
               workspace.ActivationTargetOccupancyKind.invalidDirectory =>
                 WorkspaceActivationTargetOccupancyKind.invalidDirectory,
               workspace.ActivationTargetOccupancyKind.brokenSymbolicLink =>
                 WorkspaceActivationTargetOccupancyKind.brokenSymbolicLink,
             },
             contentRelation: switch (target.contentRelation) {
               workspace.ActivationContentRelation.matchesCurrentRevision =>
                 WorkspaceActivationContentRelation.matchesCurrentRevision,
               workspace.ActivationContentRelation.differsFromCurrentRevision =>
                 WorkspaceActivationContentRelation.differsFromCurrentRevision,
               workspace.ActivationContentRelation.indeterminate =>
                 WorkspaceActivationContentRelation.indeterminate,
             },
             existingDeclaredName: target.existingDeclaredName,
             linkTarget: target.linkTarget,
           ),
       ]);

  final workspace.ActivationTakeoverDraft backendDraft;

  @override
  int get expectedRevision => backendDraft.reviewedRevision.value;

  @override
  final List<WorkspaceOccupiedActivationTarget> targets;
}

final class _PackageWorkspaceSkillDriftReview
    implements WorkspaceSkillDriftReview {
  _PackageWorkspaceSkillDriftReview(this.backendReview, this.owner)
    : skillId = WorkspaceSkillId(backendReview.managedSkillId.value),
      artifacts = List.unmodifiable([
        for (final artifact in backendReview.artifacts)
          WorkspaceDriftedArtifact(
            artifactId: artifact.artifactId,
            locationKind: switch (artifact.locationKind) {
              workspace.SkillDriftLocationKind.repositoryCopy =>
                WorkspaceDriftLocationKind.repositoryCopy,
              workspace.SkillDriftLocationKind.copyActivation =>
                WorkspaceDriftLocationKind.copyActivation,
              workspace.SkillDriftLocationKind.symbolicLinkActivation =>
                WorkspaceDriftLocationKind.symbolicLinkActivation,
            },
            driftKind: switch (artifact.driftKind) {
              workspace.SkillDriftKind.contentChanged =>
                WorkspaceDriftKind.contentChanged,
              workspace.SkillDriftKind.wrongEntryType =>
                WorkspaceDriftKind.wrongEntryType,
              workspace.SkillDriftKind.wrongLinkTarget =>
                WorkspaceDriftKind.wrongLinkTarget,
            },
            targetPath: artifact.targetPath,
            scope: artifact.scope == null ? null : _scope(artifact.scope!),
            agentIds: artifact.agentIds,
            canKeepExternal: artifact.canKeepExternal,
            canExport: artifact.canExport,
          ),
      ]);

  final workspace.SkillDriftReview backendReview;
  final Object owner;
  @override
  final WorkspaceSkillId skillId;
  @override
  final List<WorkspaceDriftedArtifact> artifacts;
  @override
  int get missingArtifactCount => backendReview.missingArtifactCount;
}

final class _PackageWorkspaceInstallTakeoverDraft
    implements WorkspaceInstallTakeoverDraft {
  _PackageWorkspaceInstallTakeoverDraft(this.backendDraft)
    : targets = List.unmodifiable([
        for (final target in backendDraft.targets)
          WorkspaceOccupiedActivationTarget(
            slotKey: target.slotKey,
            location: target.location,
            targetPath: target.targetPath,
            agentIds: target.agentIds,
            kind: switch (target.kind) {
              workspace.ActivationTargetOccupancyKind.skillDirectory =>
                WorkspaceActivationTargetOccupancyKind.skillDirectory,
              workspace.ActivationTargetOccupancyKind.skillSymbolicLink =>
                WorkspaceActivationTargetOccupancyKind.skillSymbolicLink,
              workspace.ActivationTargetOccupancyKind.file =>
                WorkspaceActivationTargetOccupancyKind.file,
              workspace.ActivationTargetOccupancyKind.invalidDirectory =>
                WorkspaceActivationTargetOccupancyKind.invalidDirectory,
              workspace.ActivationTargetOccupancyKind.brokenSymbolicLink =>
                WorkspaceActivationTargetOccupancyKind.brokenSymbolicLink,
            },
            contentRelation: switch (target.contentRelation) {
              workspace.ActivationContentRelation.matchesCurrentRevision =>
                WorkspaceActivationContentRelation.matchesCurrentRevision,
              workspace.ActivationContentRelation.differsFromCurrentRevision =>
                WorkspaceActivationContentRelation.differsFromCurrentRevision,
              workspace.ActivationContentRelation.indeterminate =>
                WorkspaceActivationContentRelation.indeterminate,
            },
            existingDeclaredName: target.existingDeclaredName,
            linkTarget: target.linkTarget,
          ),
      ]);

  final workspace.InstallTakeoverDraft backendDraft;

  @override
  int get expectedRevision => backendDraft.reviewedRevision.value;

  @override
  final List<WorkspaceOccupiedActivationTarget> targets;
}

final _lockWait = workspace.LockWaitPolicy.wait(
  timeout: const Duration(seconds: 30),
);

workspace.ActivationSelection _activationSelection({
  required WorkspaceScope scope,
  required String? projectRootId,
  required Set<String> agentIds,
}) => workspace.ActivationSelection.explicit([
  for (final agentId in agentIds)
    workspace.ActivationTarget(
      agentId: agentId,
      scope: _backendScope(scope),
      projectRootId: projectRootId,
    ),
]);

workspace.ActivationScope _backendScope(WorkspaceScope source) =>
    switch (source) {
      WorkspaceScope.global => workspace.ActivationScope.global,
      WorkspaceScope.project => workspace.ActivationScope.project,
    };

WorkspaceScope _scope(workspace.ActivationScope source) => switch (source) {
  workspace.ActivationScope.global => WorkspaceScope.global,
  workspace.ActivationScope.project => WorkspaceScope.project,
};

/// Translates the user's global Activation preference for one request.
///
/// Project Activations stay on automatic, which the engine resolves to a copy
/// so checked-in project content never depends on this device's Workspace. An
/// adoption can land in both scopes ([scope] is null), so only a copy is
/// forwarded there: a strict link request could fail the whole adoption and
/// would put a link inside a project.
workspace.RequestedActivationMode _requestedMode(
  WorkspaceActivationMethod method, {
  required WorkspaceScope? scope,
}) => switch ((method, scope)) {
  (WorkspaceActivationMethod.copy, _) => workspace.RequestedActivationMode.copy,
  (WorkspaceActivationMethod.symbolicLink, WorkspaceScope.global) =>
    workspace.RequestedActivationMode.symbolicLink,
  _ => workspace.RequestedActivationMode.automatic,
};

WorkspaceActivationMode _mode(workspace.ActivationMode source) =>
    switch (source) {
      workspace.ActivationMode.copy => WorkspaceActivationMode.copy,
      workspace.ActivationMode.symbolicLink =>
        WorkspaceActivationMode.symbolicLink,
    };

SkillActivationLocation _activation(workspace.SkillActivation source) =>
    SkillActivationLocation(
      location: source.location,
      scope: _scope(source.scope),
      mode: _mode(source.mode),
      agentIds: source.agentIds,
      projectRootId: source.projectRootId,
      projectRootPath: source.projectRootPath,
    );

WorkspaceActivationTarget _activationTarget(
  workspace.ActivationTargetInfo source,
) => WorkspaceActivationTarget(
  agentId: source.agentId,
  displayName: source.displayName,
  detected: source.detected,
  location: source.location,
  scope: _scope(source.scope),
  projectRootId: source.projectRootId,
  projectRootPath: source.projectRootPath,
);

workspace.SourceDescriptor? _source(SkillSourceInput source) =>
    switch (source.kind) {
      WorkspaceSourceKind.local => workspace.LocalSourceDescriptor(
        locator: source.locator,
        skillPath: source.skillPath,
      ),
      WorkspaceSourceKind.git => workspace.GitSourceDescriptor(
        locator: source.locator,
        ref: source.ref,
        repositorySubpath: source.repositorySubpath,
        skillPath: source.skillPath,
      ),
      WorkspaceSourceKind.wellKnown => workspace.WellKnownSourceDescriptor(
        locator: source.locator,
        skillPath: source.skillPath,
      ),
      WorkspaceSourceKind.adoptedSnapshot => null,
    };

SkillSourceProvenance _sourceProvenance(workspace.SourceDescriptor source) =>
    switch (source) {
      workspace.LocalSourceDescriptor() => SkillSourceProvenance(
        kind: WorkspaceSourceKind.local,
        locator: source.locator,
        skillPath: source.skillPath,
      ),
      workspace.GitSourceDescriptor() => SkillSourceProvenance(
        kind: WorkspaceSourceKind.git,
        locator: source.locator,
        ref: source.ref,
        repositorySubpath: source.repositorySubpath,
        skillPath: source.skillPath,
      ),
      workspace.WellKnownSourceDescriptor() => SkillSourceProvenance(
        kind: WorkspaceSourceKind.wellKnown,
        locator: source.locator,
        skillPath: source.skillPath,
      ),
      workspace.AdoptedSnapshotSourceDescriptor() => SkillSourceProvenance(
        kind: WorkspaceSourceKind.adoptedSnapshot,
        locator: source.authoritativeLocation,
      ),
    };

WorkspaceErrorCode _errorCode(
  workspace.SkillsErrorCode source,
) => switch (source) {
  workspace.SkillsErrorCode.sourceUnavailable =>
    WorkspaceErrorCode.sourceUnavailable,
  workspace.SkillsErrorCode.sourceAuthenticationRequired =>
    WorkspaceErrorCode.sourceAuthenticationRequired,
  workspace.SkillsErrorCode.gitUnavailable => WorkspaceErrorCode.gitUnavailable,
  workspace.SkillsErrorCode.gitFailed => WorkspaceErrorCode.gitFailed,
  workspace.SkillsErrorCode.developerToolsRequired =>
    WorkspaceErrorCode.developerToolsRequired,
  workspace.SkillsErrorCode.transportRejected =>
    WorkspaceErrorCode.transportRejected,
  workspace.SkillsErrorCode.httpFailure => WorkspaceErrorCode.httpFailure,
  workspace.SkillsErrorCode.digestMismatch => WorkspaceErrorCode.digestMismatch,
  workspace.SkillsErrorCode.archiveInvalid => WorkspaceErrorCode.archiveInvalid,
  workspace.SkillsErrorCode.skillNotFound => WorkspaceErrorCode.skillNotFound,
  workspace.SkillsErrorCode.staleSnapshot => WorkspaceErrorCode.staleSnapshot,
  workspace.SkillsErrorCode.staleInstallTakeover =>
    WorkspaceErrorCode.staleInstallTakeover,
  workspace.SkillsErrorCode.staleActivationTakeover =>
    WorkspaceErrorCode.staleActivationTakeover,
  workspace.SkillsErrorCode.invalidSkill => WorkspaceErrorCode.invalidSkill,
  workspace.SkillsErrorCode.unsupportedSkillName =>
    WorkspaceErrorCode.unsupportedSkillName,
  workspace.SkillsErrorCode.skillContentLimitExceeded =>
    WorkspaceErrorCode.skillContentLimitExceeded,
  workspace.SkillsErrorCode.duplicateSkillSlot =>
    WorkspaceErrorCode.duplicateSkillSlot,
  workspace.SkillsErrorCode.sourceReplacementRequired =>
    WorkspaceErrorCode.sourceReplacementRequired,
  workspace.SkillsErrorCode.updateUnsupported =>
    WorkspaceErrorCode.updateUnsupported,
  workspace.SkillsErrorCode.externalConflict =>
    WorkspaceErrorCode.externalConflict,
  workspace.SkillsErrorCode.activationUnavailable =>
    WorkspaceErrorCode.activationUnavailable,
  workspace.SkillsErrorCode.activationUnsupported =>
    WorkspaceErrorCode.activationUnsupported,
  workspace.SkillsErrorCode.projectRootNotFound =>
    WorkspaceErrorCode.projectRootNotFound,
  workspace.SkillsErrorCode.invalidProjectRoot =>
    WorkspaceErrorCode.invalidProjectRoot,
  workspace.SkillsErrorCode.projectRootConflict =>
    WorkspaceErrorCode.projectRootConflict,
  workspace.SkillsErrorCode.agentNotFound => WorkspaceErrorCode.agentNotFound,
  workspace.SkillsErrorCode.duplicateAgentId =>
    WorkspaceErrorCode.duplicateAgentId,
  workspace.SkillsErrorCode.personalTagNotFound =>
    WorkspaceErrorCode.personalTagNotFound,
  workspace.SkillsErrorCode.duplicatePersonalTag =>
    WorkspaceErrorCode.duplicatePersonalTag,
  workspace.SkillsErrorCode.repositoryBusy => WorkspaceErrorCode.repositoryBusy,
  workspace.SkillsErrorCode.operationCancelled =>
    WorkspaceErrorCode.operationCancelled,
  workspace.SkillsErrorCode.unsupportedStateVersion =>
    WorkspaceErrorCode.unsupportedStateVersion,
  workspace.SkillsErrorCode.unsupportedJournalVersion =>
    WorkspaceErrorCode.unsupportedJournalVersion,
  workspace.SkillsErrorCode.stateCorrupt => WorkspaceErrorCode.stateCorrupt,
  workspace.SkillsErrorCode.journalCorrupt => WorkspaceErrorCode.journalCorrupt,
  workspace.SkillsErrorCode.journalMaintenanceFailed =>
    WorkspaceErrorCode.journalMaintenanceFailed,
  workspace.SkillsErrorCode.rollbackFailed => WorkspaceErrorCode.rollbackFailed,
  workspace.SkillsErrorCode.recoveryFailed => WorkspaceErrorCode.recoveryFailed,
  workspace.SkillsErrorCode.ioFailure => WorkspaceErrorCode.ioFailure,
  workspace.SkillsErrorCode.operationFailed =>
    WorkspaceErrorCode.operationFailed,
  workspace.SkillsErrorCode.migrationFailed =>
    WorkspaceErrorCode.migrationFailed,
  workspace.SkillsErrorCode.controlPlaneCorrupt =>
    WorkspaceErrorCode.controlPlaneCorrupt,
  workspace.SkillsErrorCode.revisionStoreCorrupt =>
    WorkspaceErrorCode.revisionStoreCorrupt,
  workspace.SkillsErrorCode.invalidEffectiveFilePath =>
    WorkspaceErrorCode.invalidEffectiveFilePath,
  workspace.SkillsErrorCode.effectiveFileNotFound =>
    WorkspaceErrorCode.effectiveFileNotFound,
  workspace.SkillsErrorCode.finalizationRecoveryFailed =>
    WorkspaceErrorCode.finalizationRecoveryFailed,
  workspace.SkillsErrorCode.dirtyDraftResolutionRequired =>
    WorkspaceErrorCode.dirtyDraftResolutionRequired,
  workspace.SkillsErrorCode.updateCandidateResolutionRequired =>
    WorkspaceErrorCode.updateCandidateResolutionRequired,
  workspace.SkillsErrorCode.draftChangedDuringPublish =>
    WorkspaceErrorCode.draftChangedDuringPublish,
  workspace.SkillsErrorCode.declaredNameChangeNotAllowed =>
    WorkspaceErrorCode.declaredNameChangeNotAllowed,
  workspace.SkillsErrorCode.historicalNameMismatch =>
    WorkspaceErrorCode.historicalNameMismatch,
  workspace.SkillsErrorCode.staleDriftReview =>
    WorkspaceErrorCode.staleDriftReview,
  workspace.SkillsErrorCode.driftResolutionUnavailable =>
    WorkspaceErrorCode.driftResolutionUnavailable,
};

WorkspaceWarningCode _warningCode(workspace.SkillsWarningCode source) =>
    WorkspaceWarningCode.values.byName(source.name);
