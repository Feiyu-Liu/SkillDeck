import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:skills_workspace/skills_workspace.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

void main() {
  test(
    'Install takeover preserves an occupied link until stale-safe confirmation',
    () async {
      final fixture = await _FacadeFixture.create();
      addTearDown(fixture.dispose);
      await fixture.activationRoot.create(recursive: true);
      final firstLegacyTarget = File(
        path.join(fixture.temporaryRoot.path, 'legacy-target-a'),
      );
      final secondLegacyTarget = File(
        path.join(fixture.temporaryRoot.path, 'legacy-target-b'),
      );
      await firstLegacyTarget.writeAsString('legacy a', flush: true);
      await secondLegacyTarget.writeAsString('legacy b', flush: true);
      final occupied = Link(fixture.activationSkillPath);
      await occupied.create(firstLegacyTarget.path);

      final repository = fixture.createRepository();
      await _expectSuccess(repository.open());
      final request = InstallRequest(
        source: fixture.primarySource,
        activationSelection: ActivationSelection.explicit(<ActivationTarget>[
          ActivationTarget(agentId: _agentId, scope: ActivationScope.global),
        ]),
        activationMode: RequestedActivationMode.copy,
      );

      final firstAttempt = await _expectSuccess(repository.install(request));
      expect(firstAttempt, isA<InstallTakeoverRequired>());
      final firstDraft = (firstAttempt as InstallTakeoverRequired).draft;
      expect(firstDraft.targets, hasLength(1));
      expect(
        firstDraft.targets.single.kind,
        ActivationTargetOccupancyKind.brokenSymbolicLink,
      );
      expect(firstDraft.targets.single.linkTarget, firstLegacyTarget.path);
      expect(repository.snapshot.managedSkills, isEmpty);
      expect(
        await FileSystemEntity.type(occupied.path, followLinks: false),
        FileSystemEntityType.link,
      );
      expect(await occupied.target(), firstLegacyTarget.path);
      expect(
        _workspaceRowCount(fixture.workspaceRoot, 'operation_journals'),
        0,
      );
      expect(_workspaceRowCount(fixture.workspaceRoot, 'operation_records'), 0);

      await occupied.delete();
      await occupied.create(secondLegacyTarget.path);
      final stale = await repository
          .confirmInstallTakeover(
            ConfirmInstallTakeoverRequest(draft: firstDraft),
          )
          .completed;
      expect(stale, isA<SkillsFailure<MutationReport>>());
      expect(
        (stale as SkillsFailure<MutationReport>).code,
        SkillsErrorCode.staleInstallTakeover,
      );
      expect(repository.snapshot.managedSkills, isEmpty);
      expect(await occupied.target(), secondLegacyTarget.path);
      expect(
        _workspaceRowCount(fixture.workspaceRoot, 'operation_journals'),
        0,
      );
      expect(_workspaceRowCount(fixture.workspaceRoot, 'operation_records'), 0);

      final refreshedAttempt = await _expectSuccess(
        repository.install(request),
      );
      final refreshedDraft =
          (refreshedAttempt as InstallTakeoverRequired).draft;
      final installed = await _expectSuccess(
        repository.confirmInstallTakeover(
          ConfirmInstallTakeoverRequest(draft: refreshedDraft),
        ),
      );

      expect(installed.affectedSkillIds, hasLength(1));
      expect(repository.snapshot.managedSkills, hasLength(1));
      expect(
        await FileSystemEntity.type(occupied.path, followLinks: false),
        FileSystemEntityType.directory,
      );
      await fixture.expectActivationFile('notes.md', _baseNotes);
      expect(await firstLegacyTarget.readAsString(), 'legacy a');
      expect(await secondLegacyTarget.readAsString(), 'legacy b');
      await _expectSuccess(repository.close());
    },
    skip: Platform.isWindows
        ? 'Creating symbolic links is not guaranteed on Windows CI.'
        : false,
  );

  test(
    'public facade completes the managed Skill business lifecycle',
    () async {
      final fixture = await _FacadeFixture.create();
      addTearDown(fixture.dispose);

      var repository = fixture.createRepository();
      await _expectSuccess(repository.open());

      final inspected = await _expectSuccess(
        repository.inspectSource(
          InspectSourceRequest(source: fixture.primarySource),
        ),
      );
      expect(inspected.candidates, hasLength(1));
      expect(inspected.candidates.single.declaredName, _skillName);

      final installed =
          (await _expectSuccess(
                    repository.install(
                      InstallRequest(
                        source: fixture.primarySource,
                        activationSelection: const ActivationSelection.none(),
                      ),
                    ),
                    label: 'install',
                  )
                  as InstallCompleted)
              .report;
      final managedSkillId = installed.affectedSkillIds.single;
      expect(installed.snapshot.managedSkills, hasLength(1));
      expect(installed.snapshot.managedSkills.single.activations, isEmpty);
      await _expectEffectiveText(
        repository: repository,
        managedSkillId: managedSkillId,
        relativePath: 'notes.md',
        expected: _baseNotes,
      );

      final concurrentMutations =
          await Future.wait(<Future<SkillsResult<RepositorySnapshot>>>[
            repository
                .setFavorite(
                  SetFavoriteRequest(
                    managedSkillId: managedSkillId,
                    isFavorite: true,
                  ),
                )
                .completed,
            repository
                .saveNote(
                  SaveNoteRequest(
                    managedSkillId: managedSkillId,
                    text: 'Concurrent writer lock proof',
                  ),
                )
                .completed,
          ]);
      expect(
        concurrentMutations.where((result) => result.isSuccess),
        hasLength(1),
      );
      expect(
        concurrentMutations.whereType<SkillsFailure<RepositorySnapshot>>().map(
          (failure) => failure.code,
        ),
        <SkillsErrorCode>[SkillsErrorCode.staleSnapshot],
      );
      if (!repository.snapshot.findSkill(managedSkillId)!.favorite.isFavorite) {
        await _expectSuccess(
          repository.setFavorite(
            SetFavoriteRequest(
              managedSkillId: managedSkillId,
              isFavorite: true,
            ),
          ),
        );
      }
      if (repository.snapshot.findSkill(managedSkillId)!.note == null) {
        await _expectSuccess(
          repository.saveNote(
            SaveNoteRequest(
              managedSkillId: managedSkillId,
              text: 'Concurrent writer lock proof',
            ),
          ),
        );
      }
      expect(
        repository.snapshot.findSkill(managedSkillId)!.favorite.isFavorite,
        isTrue,
      );
      expect(
        repository.snapshot.findSkill(managedSkillId)!.note?.text,
        'Concurrent writer lock proof',
      );

      final activationTargets = await _expectSuccess(
        repository.inspectActivationTargets(
          InspectActivationTargetsRequest(scope: ActivationScope.global),
        ),
      );
      expect(
        activationTargets,
        contains(
          isA<ActivationTargetInfo>()
              .having((target) => target.agentId, 'agentId', _agentId)
              .having(
                (target) => target.location,
                'location',
                fixture.activationRoot.path,
              ),
        ),
      );

      final activated = await _expectSuccess(
        repository.activate(
          ActivateRequest(
            managedSkillIds: <ManagedSkillId>{managedSkillId},
            selection: ActivationSelection.explicit(<ActivationTarget>[
              ActivationTarget(
                agentId: _agentId,
                scope: ActivationScope.global,
              ),
            ]),
            mode: RequestedActivationMode.copy,
          ),
        ),
      );
      expect(activated, isA<ActivationCompleted>());
      expect(
        repository.snapshot.findSkill(managedSkillId)?.activations,
        hasLength(1),
      );
      await fixture.expectActivationFile('notes.md', _baseNotes);

      final customizationDraft = await _expectSuccess(
        repository.ensureDraft(
          EnsureDraftRequest(managedSkillId: managedSkillId),
        ),
      );
      await File(
        path.join(customizationDraft.path, 'notes.md'),
      ).writeAsString(_localNotes, flush: true);
      final customized = await _expectSuccess(
        repository.publishDraft(
          PublishDraftRequest(managedSkillId: managedSkillId),
        ),
      );
      expect(customized.affectedSkillIds, <ManagedSkillId>{managedSkillId});
      await fixture.expectActivationFile('notes.md', _localNotes);
      await _expectEffectiveText(
        repository: repository,
        managedSkillId: managedSkillId,
        relativePath: 'notes.md',
        expected: _localNotes,
      );

      await fixture.writePrimarySkill(notes: _upstreamNotes);
      final conflictedUpdate = await _expectSuccess(
        repository.update(
          UpdateRequest(managedSkillIds: <ManagedSkillId>{managedSkillId}),
        ),
      );
      expect(conflictedUpdate.affectedSkillIds, <ManagedSkillId>{
        managedSkillId,
      });
      await _expectEffectiveText(
        repository: repository,
        managedSkillId: managedSkillId,
        relativePath: 'notes.md',
        expected: _localNotes,
      );
      final conflictSession = await _expectSuccess(
        repository.inspectUpdateCandidate(
          InspectUpdateCandidateRequest(managedSkillId: managedSkillId),
        ),
      );
      expect(conflictSession?.status, UpdateCandidateStatus.conflicted);
      expect(
        conflictSession?.conflicts,
        contains(
          isA<UpdateConflict>()
              .having((conflict) => conflict.path, 'path', 'notes.md')
              .having(
                (conflict) => conflict.resolutionState,
                'resolutionState',
                UpdateConflictResolutionState.unresolved,
              ),
        ),
      );
      final conflictDraft = await _expectSuccess(
        repository.inspectDraft(
          InspectDraftRequest(managedSkillId: managedSkillId),
        ),
      );
      expect(conflictDraft?.purpose, DraftPurpose.updateCandidateResolution);
      await File(
        path.join(conflictDraft!.path, 'notes.md'),
      ).writeAsString(_resolvedNotes, flush: true);
      await _expectSuccess(
        repository.resolveUpdateConflict(
          ResolveUpdateConflictRequest(
            managedSkillId: managedSkillId,
            path: 'notes.md',
            resolutionState: UpdateConflictResolutionState.resolved,
          ),
        ),
      );
      await _expectSuccess(
        repository.publishUpdateCandidate(
          PublishUpdateCandidateRequest(managedSkillId: managedSkillId),
        ),
      );
      expect(
        repository.snapshot.findSkill(managedSkillId)?.updateCandidate,
        isNull,
      );
      await fixture.expectActivationFile('notes.md', _resolvedNotes);
      await _expectEffectiveText(
        repository: repository,
        managedSkillId: managedSkillId,
        relativePath: 'notes.md',
        expected: _resolvedNotes,
      );

      final largeDraft = await _expectSuccess(
        repository.ensureDraft(
          EnsureDraftRequest(managedSkillId: managedSkillId),
        ),
      );
      await _writeNumberedFiles(
        largeDraft.path,
        prefix: 'local',
        count: _validationFileCount,
      );
      await _expectSuccess(
        repository.publishDraft(
          PublishDraftRequest(managedSkillId: managedSkillId),
        ),
      );
      await fixture.writePrimarySkill(
        notes: _upstreamNotes,
        numberedPrefix: 'upstream',
        numberedCount: _validationFileCount,
      );
      await _expectSuccess(
        repository.update(
          UpdateRequest(managedSkillIds: <ManagedSkillId>{managedSkillId}),
        ),
      );
      final validationSession = await _expectSuccess(
        repository.inspectUpdateCandidate(
          InspectUpdateCandidateRequest(managedSkillId: managedSkillId),
        ),
      );
      expect(validationSession?.status, UpdateCandidateStatus.validationFailed);
      expect(validationSession?.validationCode, 'mergedSkillFileLimitExceeded');
      expect(validationSession?.conflicts, isEmpty);

      final validationDraft = repository.snapshot
          .findSkill(managedSkillId)!
          .draft!;
      expect(validationDraft.purpose, DraftPurpose.updateCandidateResolution);
      await _deleteNumberedFiles(validationDraft.path, prefix: 'local');
      await _expectSuccess(
        repository.publishUpdateCandidate(
          PublishUpdateCandidateRequest(managedSkillId: managedSkillId),
        ),
      );
      expect(
        repository.snapshot.findSkill(managedSkillId)?.updateCandidate,
        isNull,
      );
      expect(
        await File(
          path.join(fixture.activationSkillPath, 'upstream-000.md'),
        ).exists(),
        isTrue,
      );
      expect(
        await File(
          path.join(fixture.activationSkillPath, 'local-000.md'),
        ).exists(),
        isFalse,
      );

      final operationHistory = await _expectSuccess(
        repository.inspectOperationHistory(
          OperationHistoryRequest(managedSkillId: managedSkillId),
        ),
      );
      expect(
        operationHistory.entries.map((entry) => entry.kind),
        containsAll(<WorkspaceOperationKind>[
          WorkspaceOperationKind.install,
          WorkspaceOperationKind.activate,
          WorkspaceOperationKind.publishDraft,
          WorkspaceOperationKind.update,
          WorkspaceOperationKind.publishUpdateCandidate,
        ]),
      );
      final publishedHistory = await _expectSuccess(
        repository.inspectPublishedHistory(
          PublishedHistoryRequest(managedSkillId: managedSkillId),
        ),
      );
      final installedRevision = publishedHistory.revisions.singleWhere(
        (revision) => revision.kind == WorkspaceOperationKind.install,
      );
      final currentRevision = publishedHistory.revisions.first;
      final diff = await _expectSuccess(
        repository.inspectDiff(
          InspectDiffRequest(
            managedSkillId: managedSkillId,
            from: installedRevision.reference,
            to: currentRevision.reference,
          ),
        ),
      );
      expect(diff.files, isNotEmpty);

      await _expectSuccess(
        repository.restorePublish(
          RestorePublishRequest(
            managedSkillId: managedSkillId,
            selectedRevision: installedRevision.reference,
          ),
        ),
      );
      await fixture.expectActivationFile('notes.md', _baseNotes);
      await _expectEffectiveText(
        repository: repository,
        managedSkillId: managedSkillId,
        relativePath: 'notes.md',
        expected: _baseNotes,
      );
      expect(
        await File(
          path.join(fixture.activationSkillPath, 'upstream-000.md'),
        ).exists(),
        isFalse,
      );

      await fixture.writeReplacementSkill();
      final identityBeforeReplacement = repository.snapshot.findSkill(
        managedSkillId,
      )!;
      await _expectSuccess(
        repository.replaceSource(
          ReplaceSourceRequest(
            managedSkillId: managedSkillId,
            source: fixture.replacementSource,
            intent: DestructiveIntent(
              reviewedRevision: repository.snapshot.revision,
            ),
          ),
        ),
      );
      final replaced = repository.snapshot.findSkill(managedSkillId)!;
      expect(replaced.id, identityBeforeReplacement.id);
      expect(replaced.slotKey, identityBeforeReplacement.slotKey);
      expect(replaced.description, _replacementDescription);
      expect(replaced.source, isA<LocalSourceDescriptor>());
      await fixture.expectActivationFile('replacement.md', _replacementBody);
      await _expectEffectiveText(
        repository: repository,
        managedSkillId: managedSkillId,
        relativePath: 'replacement.md',
        expected: _replacementBody,
      );

      await _expectSuccess(repository.close());
      await _makeTemporaryTreeWritable(fixture.activationSkillPath);
      await Directory(fixture.activationSkillPath).delete(recursive: true);

      repository = fixture.createRepository();
      final reopened = await _expectSuccess(repository.open());
      expect(
        reopened.findSkill(managedSkillId)?.description,
        _replacementDescription,
      );
      await _expectSuccess(
        repository.validateWorkspace(const ValidateWorkspaceRequest()),
      );
      await fixture.expectActivationFile('replacement.md', _replacementBody);

      await _expectSuccess(
        repository.remove(
          RemoveRequest(
            managedSkillIds: <ManagedSkillId>{managedSkillId},
            intent: DestructiveIntent(
              reviewedRevision: repository.snapshot.revision,
            ),
          ),
        ),
      );
      expect(repository.snapshot.findSkill(managedSkillId), isNull);
      expect(await Directory(fixture.activationSkillPath).exists(), isFalse);
      await _expectSuccess(repository.close());

      repository = fixture.createRepository();
      final reopenedAfterRemoval = await _expectSuccess(repository.open());
      expect(reopenedAfterRemoval.managedSkills, isEmpty);
      expect(await Directory(fixture.activationSkillPath).exists(), isFalse);
      await _expectSuccess(repository.close());
    },
    timeout: _validationScenarioTimeout,
  );

  test(
    'Update Candidate Session survives reopen and can be published',
    () async {
      final fixture = await _FacadeFixture.create();
      addTearDown(fixture.dispose);

      var repository = fixture.createRepository();
      await _expectSuccess(repository.open());
      final installed =
          (await _expectSuccess(
                    repository.install(
                      InstallRequest(
                        source: fixture.primarySource,
                        activationSelection: const ActivationSelection.none(),
                      ),
                    ),
                  )
                  as InstallCompleted)
              .report;
      final managedSkillId = installed.affectedSkillIds.single;

      final customizationDraft = await _expectSuccess(
        repository.ensureDraft(
          EnsureDraftRequest(managedSkillId: managedSkillId),
        ),
      );
      await File(
        path.join(customizationDraft.path, 'notes.md'),
      ).writeAsString(_localNotes, flush: true);
      await _expectSuccess(
        repository.publishDraft(
          PublishDraftRequest(managedSkillId: managedSkillId),
        ),
      );
      final effectiveBeforeUpdate = repository.snapshot
          .findSkill(managedSkillId)!
          .currentRevision;

      await fixture.writePrimarySkill(notes: _upstreamNotes);
      await _expectSuccess(
        repository.update(
          UpdateRequest(managedSkillIds: <ManagedSkillId>{managedSkillId}),
        ),
      );
      final sessionBeforeReopen = await _expectSuccess(
        repository.inspectUpdateCandidate(
          InspectUpdateCandidateRequest(managedSkillId: managedSkillId),
        ),
      );
      expect(sessionBeforeReopen?.status, UpdateCandidateStatus.conflicted);
      expect(
        sessionBeforeReopen?.conflicts.single.resolutionState,
        UpdateConflictResolutionState.unresolved,
      );
      final draftBeforeReopen = await _expectSuccess(
        repository.inspectDraft(
          InspectDraftRequest(managedSkillId: managedSkillId),
        ),
      );
      expect(
        draftBeforeReopen?.purpose,
        DraftPurpose.updateCandidateResolution,
      );
      final draftBytesBeforeReopen = await File(
        path.join(draftBeforeReopen!.path, 'notes.md'),
      ).readAsString();
      expect(
        repository.snapshot.findSkill(managedSkillId)!.currentRevision,
        effectiveBeforeUpdate,
        reason: 'an unresolved candidate must not advance Effective Revision',
      );

      await _expectSuccess(repository.close());
      repository = fixture.createRepository();
      final reopened = await _expectSuccess(repository.open());
      final reopenedSkill = reopened.findSkill(managedSkillId)!;
      expect(reopenedSkill.currentRevision, effectiveBeforeUpdate);
      expect(reopenedSkill.updateCandidate, sessionBeforeReopen);

      final reopenedSession = await _expectSuccess(
        repository.inspectUpdateCandidate(
          InspectUpdateCandidateRequest(managedSkillId: managedSkillId),
        ),
      );
      expect(reopenedSession, sessionBeforeReopen);
      final reopenedDraft = await _expectSuccess(
        repository.inspectDraft(
          InspectDraftRequest(managedSkillId: managedSkillId),
        ),
      );
      expect(reopenedDraft, draftBeforeReopen);
      expect(
        await File(path.join(reopenedDraft!.path, 'notes.md')).readAsString(),
        draftBytesBeforeReopen,
      );

      await File(
        path.join(reopenedDraft.path, 'notes.md'),
      ).writeAsString(_resolvedNotes, flush: true);
      await _expectSuccess(
        repository.resolveUpdateConflict(
          ResolveUpdateConflictRequest(
            managedSkillId: managedSkillId,
            path: 'notes.md',
            resolutionState: UpdateConflictResolutionState.resolved,
          ),
        ),
      );
      await _expectSuccess(
        repository.publishUpdateCandidate(
          PublishUpdateCandidateRequest(managedSkillId: managedSkillId),
        ),
      );

      final published = repository.snapshot.findSkill(managedSkillId)!;
      expect(published.updateCandidate, isNull);
      expect(published.draft, isNull);
      expect(published.currentRevision, isNot(effectiveBeforeUpdate));
      final history = await _expectSuccess(
        repository.inspectPublishedHistory(
          PublishedHistoryRequest(managedSkillId: managedSkillId),
        ),
      );
      expect(
        history.revisions.first.kind,
        WorkspaceOperationKind.publishUpdateCandidate,
      );
      await _expectSuccess(repository.close());
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'Update Candidate Session survives reopen and can be abandoned',
    () async {
      final fixture = await _FacadeFixture.create();
      addTearDown(fixture.dispose);

      var repository = fixture.createRepository();
      await _expectSuccess(repository.open());
      final installed =
          (await _expectSuccess(
                    repository.install(
                      InstallRequest(
                        source: fixture.primarySource,
                        activationSelection: const ActivationSelection.none(),
                      ),
                    ),
                  )
                  as InstallCompleted)
              .report;
      final managedSkillId = installed.affectedSkillIds.single;
      await _expectSuccess(
        repository.activate(
          ActivateRequest(
            managedSkillIds: <ManagedSkillId>{managedSkillId},
            selection: ActivationSelection.explicit(<ActivationTarget>[
              ActivationTarget(
                agentId: _agentId,
                scope: ActivationScope.global,
              ),
            ]),
            mode: RequestedActivationMode.copy,
          ),
        ),
      );

      final customizationDraft = await _expectSuccess(
        repository.ensureDraft(
          EnsureDraftRequest(managedSkillId: managedSkillId),
        ),
      );
      await File(
        path.join(customizationDraft.path, 'notes.md'),
      ).writeAsString(_localNotes, flush: true);
      await _expectSuccess(
        repository.publishDraft(
          PublishDraftRequest(managedSkillId: managedSkillId),
        ),
      );
      final pointersBeforeCandidate = _readRevisionPointers(
        fixture.workspaceRoot,
        managedSkillId,
      );
      final revisionBeforeCandidate = repository.snapshot
          .findSkill(managedSkillId)!
          .currentRevision;
      final publishedHistoryBeforeCandidate = _publishedHistoryEvidence(
        await _expectSuccess(
          repository.inspectPublishedHistory(
            PublishedHistoryRequest(managedSkillId: managedSkillId),
          ),
        ),
      );
      final repositoryCopyBeforeCandidate = await File(
        path.join(fixture.repositoryCopySkillPath, 'notes.md'),
      ).readAsString();
      final activationBeforeCandidate = await File(
        path.join(fixture.activationSkillPath, 'notes.md'),
      ).readAsString();

      await fixture.writePrimarySkill(notes: _upstreamNotes);
      await _expectSuccess(
        repository.update(
          UpdateRequest(managedSkillIds: <ManagedSkillId>{managedSkillId}),
        ),
      );
      final sessionBeforeReopen = await _expectSuccess(
        repository.inspectUpdateCandidate(
          InspectUpdateCandidateRequest(managedSkillId: managedSkillId),
        ),
      );
      expect(sessionBeforeReopen?.status, UpdateCandidateStatus.conflicted);
      expect(
        _readRevisionPointers(fixture.workspaceRoot, managedSkillId),
        pointersBeforeCandidate,
      );
      expect(
        repository.snapshot.findSkill(managedSkillId)!.currentRevision,
        revisionBeforeCandidate,
      );
      expect(
        await File(
          path.join(fixture.repositoryCopySkillPath, 'notes.md'),
        ).readAsString(),
        repositoryCopyBeforeCandidate,
      );
      expect(
        await File(
          path.join(fixture.activationSkillPath, 'notes.md'),
        ).readAsString(),
        activationBeforeCandidate,
      );

      await _expectSuccess(repository.close());
      repository = fixture.createRepository();
      final reopened = await _expectSuccess(repository.open());
      expect(
        reopened.findSkill(managedSkillId)?.updateCandidate,
        sessionBeforeReopen,
      );
      expect(
        _readRevisionPointers(fixture.workspaceRoot, managedSkillId),
        pointersBeforeCandidate,
      );
      await _expectSuccess(
        repository.abandonUpdateCandidate(
          AbandonUpdateCandidateRequest(managedSkillId: managedSkillId),
        ),
      );

      final abandoned = repository.snapshot.findSkill(managedSkillId)!;
      expect(abandoned.updateCandidate, isNull);
      expect(abandoned.draft, isNull);
      expect(abandoned.currentRevision, revisionBeforeCandidate);
      expect(
        _readRevisionPointers(fixture.workspaceRoot, managedSkillId),
        pointersBeforeCandidate,
        reason: 'Abandon must not advance Upstream or Effective pointers',
      );
      expect(
        await File(
          path.join(fixture.repositoryCopySkillPath, 'notes.md'),
        ).readAsString(),
        repositoryCopyBeforeCandidate,
      );
      expect(
        await File(
          path.join(fixture.activationSkillPath, 'notes.md'),
        ).readAsString(),
        activationBeforeCandidate,
      );
      final publishedHistoryAfterAbandon = _publishedHistoryEvidence(
        await _expectSuccess(
          repository.inspectPublishedHistory(
            PublishedHistoryRequest(managedSkillId: managedSkillId),
          ),
        ),
      );
      expect(
        publishedHistoryAfterAbandon,
        publishedHistoryBeforeCandidate,
        reason: 'Abandon must not append a Published Revision',
      );
      await _expectSuccess(repository.close());
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'validation-failed Session survives reopen and can be repaired and published',
    () async {
      final fixture = await _FacadeFixture.create();
      addTearDown(fixture.dispose);
      final baseline = await _createValidationFailedCandidate(fixture);
      var repository = baseline.repository;

      expect(baseline.session.status, UpdateCandidateStatus.validationFailed);
      expect(baseline.session.validationCode, 'mergedSkillFileLimitExceeded');
      expect(
        _readRevisionPointers(fixture.workspaceRoot, baseline.managedSkillId),
        baseline.pointers,
      );
      expect(await _materializedFilePresence(fixture, 'local-000.md'), (
        repositoryCopy: true,
        activation: true,
      ));
      expect(await _materializedFilePresence(fixture, 'upstream-000.md'), (
        repositoryCopy: false,
        activation: false,
      ));

      await _expectSuccess(repository.close());
      repository = fixture.createRepository();
      final reopened = await _expectSuccess(repository.open());
      expect(
        reopened.findSkill(baseline.managedSkillId)?.updateCandidate,
        baseline.session,
      );
      expect(
        reopened.findSkill(baseline.managedSkillId)?.currentRevision,
        baseline.revision,
      );
      expect(
        _readRevisionPointers(fixture.workspaceRoot, baseline.managedSkillId),
        baseline.pointers,
      );
      final reopenedDraft = await _expectSuccess(
        repository.inspectDraft(
          InspectDraftRequest(managedSkillId: baseline.managedSkillId),
        ),
      );
      expect(reopenedDraft?.purpose, DraftPurpose.updateCandidateResolution);
      await _deleteNumberedFiles(reopenedDraft!.path, prefix: 'local');
      await _expectSuccess(
        repository.publishUpdateCandidate(
          PublishUpdateCandidateRequest(
            managedSkillId: baseline.managedSkillId,
          ),
        ),
      );

      final published = repository.snapshot.findSkill(baseline.managedSkillId)!;
      expect(published.updateCandidate, isNull);
      expect(published.draft, isNull);
      expect(published.currentRevision, isNot(baseline.revision));
      final publishedPointers = _readRevisionPointers(
        fixture.workspaceRoot,
        baseline.managedSkillId,
      );
      expect(publishedPointers.sourceLineage, baseline.pointers.sourceLineage);
      expect(publishedPointers.upstream, isNot(baseline.pointers.upstream));
      expect(publishedPointers.effective, isNot(baseline.pointers.effective));
      expect(await _materializedFilePresence(fixture, 'local-000.md'), (
        repositoryCopy: false,
        activation: false,
      ));
      expect(await _materializedFilePresence(fixture, 'upstream-000.md'), (
        repositoryCopy: true,
        activation: true,
      ));
      final publishedHistory = _publishedHistoryEvidence(
        await _expectSuccess(
          repository.inspectPublishedHistory(
            PublishedHistoryRequest(managedSkillId: baseline.managedSkillId),
          ),
        ),
      );
      expect(
        publishedHistory.first.kind,
        WorkspaceOperationKind.publishUpdateCandidate,
      );
      expect(publishedHistory.skip(1), baseline.publishedHistory);
      await _expectSuccess(repository.close());
    },
    timeout: _validationScenarioTimeout,
  );

  test(
    'validation-failed Session survives reopen and can be abandoned',
    () async {
      final fixture = await _FacadeFixture.create();
      addTearDown(fixture.dispose);
      final baseline = await _createValidationFailedCandidate(fixture);
      var repository = baseline.repository;

      await _expectSuccess(repository.close());
      repository = fixture.createRepository();
      final reopened = await _expectSuccess(repository.open());
      expect(
        reopened.findSkill(baseline.managedSkillId)?.updateCandidate,
        baseline.session,
      );
      expect(
        _readRevisionPointers(fixture.workspaceRoot, baseline.managedSkillId),
        baseline.pointers,
      );
      await _expectSuccess(
        repository.abandonUpdateCandidate(
          AbandonUpdateCandidateRequest(
            managedSkillId: baseline.managedSkillId,
          ),
        ),
      );

      final abandoned = repository.snapshot.findSkill(baseline.managedSkillId)!;
      expect(abandoned.updateCandidate, isNull);
      expect(abandoned.draft, isNull);
      expect(abandoned.currentRevision, baseline.revision);
      expect(
        _readRevisionPointers(fixture.workspaceRoot, baseline.managedSkillId),
        baseline.pointers,
      );
      expect(await _materializedFilePresence(fixture, 'local-000.md'), (
        repositoryCopy: true,
        activation: true,
      ));
      expect(await _materializedFilePresence(fixture, 'upstream-000.md'), (
        repositoryCopy: false,
        activation: false,
      ));
      final publishedHistory = _publishedHistoryEvidence(
        await _expectSuccess(
          repository.inspectPublishedHistory(
            PublishedHistoryRequest(managedSkillId: baseline.managedSkillId),
          ),
        ),
      );
      expect(publishedHistory, baseline.publishedHistory);
      await _expectSuccess(repository.close());
    },
    timeout: _validationScenarioTimeout,
  );
}

const _agentId = 'public-facade-e2e-agent';
const _skillName = 'facade-skill';
const _description = 'Public facade E2E Skill';
const _replacementDescription = 'Replacement Source Skill';
const _baseNotes = 'base notes\n';
const _localNotes = 'locally customized notes\n';
const _upstreamNotes = 'upstream notes\n';
const _resolvedNotes = 'resolved notes\n';
const _replacementBody = 'replacement source bytes\n';
const _validationFileCount = 500;
final _validationScenarioTimeout = Timeout(
  Platform.isWindows ? const Duration(minutes: 8) : const Duration(minutes: 3),
);

typedef _RevisionPointers = ({
  String sourceLineage,
  String upstream,
  String effective,
});
typedef _PublishedHistoryEvidence = ({
  OperationSubjectReference reference,
  WorkspaceOperationKind kind,
  String contentHash,
});
typedef _ValidationCandidateBaseline = ({
  SkillsRepository repository,
  ManagedSkillId managedSkillId,
  UpdateCandidateSummary session,
  _RevisionPointers pointers,
  ManagedSkillRevisionSummary revision,
  List<_PublishedHistoryEvidence> publishedHistory,
});
typedef _MaterializedFilePresence = ({bool repositoryCopy, bool activation});

final class _FacadeFixture {
  _FacadeFixture._({
    required this.temporaryRoot,
    required this.workspaceRoot,
    required this.agentHome,
    required this.activationRoot,
    required this.primarySourceRoot,
    required this.replacementSourceRoot,
  });

  final Directory temporaryRoot;
  final Directory workspaceRoot;
  final Directory agentHome;
  final Directory activationRoot;
  final Directory primarySourceRoot;
  final Directory replacementSourceRoot;
  final List<SkillsRepository> _repositories = <SkillsRepository>[];

  static Future<_FacadeFixture> create() async {
    final temporaryRoot = await Directory.systemTemp.createTemp(
      'skills-workspace-public-facade-e2e-',
    );
    final workspaceRoot = Directory(path.join(temporaryRoot.path, 'workspace'));
    final agentHome = Directory(path.join(temporaryRoot.path, 'agent-home'));
    final activationRoot = Directory(path.join(agentHome.path, 'skills'));
    final primarySourceRoot = Directory(
      path.join(temporaryRoot.path, 'primary-source'),
    );
    final replacementSourceRoot = Directory(
      path.join(temporaryRoot.path, 'replacement-source'),
    );
    await agentHome.create(recursive: true);
    await primarySourceRoot.create(recursive: true);
    final fixture = _FacadeFixture._(
      temporaryRoot: temporaryRoot,
      workspaceRoot: workspaceRoot,
      agentHome: agentHome,
      activationRoot: activationRoot,
      primarySourceRoot: primarySourceRoot,
      replacementSourceRoot: replacementSourceRoot,
    );
    await fixture.writePrimarySkill(notes: _baseNotes);
    return fixture;
  }

  String get activationSkillPath => path.join(activationRoot.path, _skillName);

  String get repositoryCopySkillPath =>
      path.join(workspaceRoot.path, 'repository-copies', _skillName);

  LocalSourceDescriptor get primarySource => LocalSourceDescriptor(
    locator: path.normalize(primarySourceRoot.absolute.path),
  );

  LocalSourceDescriptor get replacementSource => LocalSourceDescriptor(
    locator: path.normalize(replacementSourceRoot.absolute.path),
  );

  SkillsRepository createRepository() {
    final repository = createSkillsRepository(
      SkillsRepositoryConfiguration(
        rootPath: workspaceRoot.absolute.path,
        agentHomePath: agentHome.absolute.path,
        defaultLockWaitPolicy: LockWaitPolicy.wait(
          timeout: const Duration(seconds: 10),
        ),
        additionalAgents: <AgentDefinition>[
          AgentDefinition(
            id: _agentId,
            displayName: 'Public Facade E2E Agent',
            platforms: <DesktopPlatform, AgentPlatformDefinition>{
              _platform(): AgentPlatformDefinition(
                globalSkillsPath: activationRoot.absolute.path,
              ),
            },
          ),
        ],
      ),
    );
    _repositories.add(repository);
    return repository;
  }

  Future<void> writePrimarySkill({
    required String notes,
    String? numberedPrefix,
    int numberedCount = 0,
  }) async {
    await primarySourceRoot.create(recursive: true);
    await for (final entity in primarySourceRoot.list()) {
      if (path.basename(entity.path) != 'SKILL.md' &&
          path.basename(entity.path) != 'notes.md') {
        await entity.delete(recursive: true);
      }
    }
    await _writeSkillMarkdown(primarySourceRoot.path, _description);
    await File(
      path.join(primarySourceRoot.path, 'notes.md'),
    ).writeAsString(notes, flush: true);
    if (numberedPrefix != null) {
      await _writeNumberedFiles(
        primarySourceRoot.path,
        prefix: numberedPrefix,
        count: numberedCount,
      );
    }
  }

  Future<void> writeReplacementSkill() async {
    await replacementSourceRoot.create(recursive: true);
    await _writeSkillMarkdown(
      replacementSourceRoot.path,
      _replacementDescription,
    );
    await File(
      path.join(replacementSourceRoot.path, 'replacement.md'),
    ).writeAsString(_replacementBody, flush: true);
  }

  Future<void> expectActivationFile(
    String relativePath,
    String contents,
  ) async {
    expect(
      await File(path.join(activationSkillPath, relativePath)).readAsString(),
      contents,
    );
  }

  Future<void> dispose() async {
    for (final repository in _repositories.reversed) {
      if (!repository.isOpen) continue;
      try {
        await repository.close().completed;
      } on Object {
        // Preserve the original test failure while continuing cleanup.
      }
    }
    if (await temporaryRoot.exists()) {
      try {
        await temporaryRoot.delete(recursive: true);
      } on FileSystemException {
        await _makeTemporaryTreeWritable(temporaryRoot.path);
        await temporaryRoot.delete(recursive: true);
      }
    }
  }
}

Future<void> _makeTemporaryTreeWritable(String rootPath) async {
  final ProcessResult result;
  if (Platform.isWindows) {
    final rootResult = await Process.run('attrib', <String>['-R', rootPath]);
    if (rootResult.exitCode != 0) {
      throw FileSystemException('Failed to make temporary test root writable.');
    }
    result = await Process.run('attrib', <String>[
      '-R',
      path.join(rootPath, '*'),
      '/S',
      '/D',
    ]);
  } else {
    result = await Process.run('chmod', <String>['-R', 'u+w', rootPath]);
  }
  if (result.exitCode != 0) {
    throw FileSystemException('Failed to make temporary test files writable.');
  }
}

Future<void> _writeSkillMarkdown(String rootPath, String description) =>
    File(path.join(rootPath, 'SKILL.md')).writeAsString(
      '---\n'
      'name: $_skillName\n'
      'description: $description\n'
      '---\n'
      '# Public facade E2E\n',
      flush: true,
    );

Future<void> _writeNumberedFiles(
  String rootPath, {
  required String prefix,
  required int count,
}) async {
  for (var index = 0; index < count; index += 1) {
    final number = index.toString().padLeft(3, '0');
    await File(
      path.join(rootPath, '$prefix-$number.md'),
    ).writeAsString('$prefix\n');
  }
}

Future<void> _deleteNumberedFiles(
  String rootPath, {
  required String prefix,
}) async {
  await for (final entity in Directory(rootPath).list()) {
    if (entity is File && path.basename(entity.path).startsWith('$prefix-')) {
      await entity.delete();
    }
  }
}

Future<T> _expectSuccess<T>(
  SkillsOperation<T> operation, {
  String? label,
}) async {
  final result = await operation.completed;
  expect(
    result,
    isA<SkillsSuccess<T>>(),
    reason: '${label == null ? '' : '$label: '}$result',
  );
  return result.valueOrNull as T;
}

Future<void> _expectEffectiveText({
  required SkillsRepository repository,
  required ManagedSkillId managedSkillId,
  required String relativePath,
  required String expected,
}) async {
  final manifest = await _expectSuccess(
    repository.listEffectiveFiles(
      ListEffectiveFilesRequest(managedSkillId: managedSkillId),
    ),
    label: 'list effective files',
  );
  expect(
    manifest.contentHash,
    repository.snapshot.findSkill(managedSkillId)?.currentRevision.contentHash,
  );
  final content = await _expectSuccess(
    repository.readEffectiveFile(
      ReadEffectiveFileRequest(
        managedSkillId: managedSkillId,
        expectedContentHash: manifest.contentHash,
        relativePath: relativePath,
      ),
    ),
    label: 'read effective file',
  );
  expect(utf8.decode(content.bytes, allowMalformed: false), expected);
}

Future<_ValidationCandidateBaseline> _createValidationFailedCandidate(
  _FacadeFixture fixture,
) async {
  final repository = fixture.createRepository();
  await _expectSuccess(repository.open());
  final installed =
      (await _expectSuccess(
                repository.install(
                  InstallRequest(
                    source: fixture.primarySource,
                    activationSelection: const ActivationSelection.none(),
                  ),
                ),
              )
              as InstallCompleted)
          .report;
  final managedSkillId = installed.affectedSkillIds.single;
  await _expectSuccess(
    repository.activate(
      ActivateRequest(
        managedSkillIds: <ManagedSkillId>{managedSkillId},
        selection: ActivationSelection.explicit(<ActivationTarget>[
          ActivationTarget(agentId: _agentId, scope: ActivationScope.global),
        ]),
        mode: RequestedActivationMode.copy,
      ),
    ),
  );
  final draft = await _expectSuccess(
    repository.ensureDraft(EnsureDraftRequest(managedSkillId: managedSkillId)),
  );
  await _writeNumberedFiles(
    draft.path,
    prefix: 'local',
    count: _validationFileCount,
  );
  await _expectSuccess(
    repository.publishDraft(
      PublishDraftRequest(managedSkillId: managedSkillId),
    ),
  );
  final pointers = _readRevisionPointers(fixture.workspaceRoot, managedSkillId);
  final revision = repository.snapshot
      .findSkill(managedSkillId)!
      .currentRevision;
  final publishedHistory = _publishedHistoryEvidence(
    await _expectSuccess(
      repository.inspectPublishedHistory(
        PublishedHistoryRequest(managedSkillId: managedSkillId),
      ),
    ),
  );

  await fixture.writePrimarySkill(
    notes: _upstreamNotes,
    numberedPrefix: 'upstream',
    numberedCount: _validationFileCount,
  );
  await _expectSuccess(
    repository.update(
      UpdateRequest(managedSkillIds: <ManagedSkillId>{managedSkillId}),
    ),
  );
  final session = await _expectSuccess(
    repository.inspectUpdateCandidate(
      InspectUpdateCandidateRequest(managedSkillId: managedSkillId),
    ),
  );
  if (session == null) {
    throw StateError('Expected a persisted validation-failed Session.');
  }
  return (
    repository: repository,
    managedSkillId: managedSkillId,
    session: session,
    pointers: pointers,
    revision: revision,
    publishedHistory: publishedHistory,
  );
}

Future<_MaterializedFilePresence> _materializedFilePresence(
  _FacadeFixture fixture,
  String relativePath,
) async => (
  repositoryCopy: await File(
    path.join(fixture.repositoryCopySkillPath, relativePath),
  ).exists(),
  activation: await File(
    path.join(fixture.activationSkillPath, relativePath),
  ).exists(),
);

_RevisionPointers _readRevisionPointers(
  Directory workspaceRoot,
  ManagedSkillId managedSkillId,
) {
  final database = sqlite3.open(
    path.join(workspaceRoot.path, 'workspace.sqlite'),
    mode: OpenMode.readOnly,
  );
  try {
    final rows = database.select(
      'SELECT source_lineage_id, upstream_object_id, effective_object_id '
      'FROM current_revision_selection WHERE managed_skill_id = ?',
      <Object?>[managedSkillId.value],
    );
    if (rows.length != 1) {
      throw StateError('Expected exactly one current revision selection.');
    }
    final row = rows.single;
    return (
      sourceLineage: row['source_lineage_id'] as String,
      upstream: row['upstream_object_id'] as String,
      effective: row['effective_object_id'] as String,
    );
  } finally {
    database.close();
  }
}

int _workspaceRowCount(Directory workspaceRoot, String tableName) {
  final database = sqlite3.open(
    path.join(workspaceRoot.path, 'workspace.sqlite'),
    mode: OpenMode.readOnly,
  );
  try {
    return database
            .select('SELECT COUNT(*) AS count FROM $tableName')
            .single['count']
        as int;
  } finally {
    database.close();
  }
}

List<_PublishedHistoryEvidence> _publishedHistoryEvidence(
  PublishedHistoryPage history,
) => [
  for (final revision in history.revisions)
    (
      reference: revision.reference,
      kind: revision.kind,
      contentHash: revision.contentHash,
    ),
];

DesktopPlatform _platform() {
  if (Platform.isMacOS) return DesktopPlatform.macos;
  if (Platform.isWindows) return DesktopPlatform.windows;
  return DesktopPlatform.linux;
}
