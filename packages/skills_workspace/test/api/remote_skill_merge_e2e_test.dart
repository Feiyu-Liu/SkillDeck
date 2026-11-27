import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:skills_workspace/skills_workspace.dart';
import 'package:skills_workspace/src/infrastructure/workspace_layout.dart';
import 'package:test/test.dart';

import '../support/drift_facade_fixture.dart';
import '../support/operations/remote_apply_test_support.dart';
import '../support/remote_revision_pack_fixture.dart';

void main() {
  late DriftFacadeFixture fixture;
  late RemoteRevisionPackFixture donor;
  late SkillsRepository repository;
  late ManagedSkillId skill;
  late RevisionId local;

  Future<RevisionSelection> inspectSelection() async => (await driftSuccess(
    repository.inspectRevisionSelections(
      InspectRevisionSelectionsRequest(managedSkillIds: {skill}),
    ),
  )).selections[skill]!;

  setUp(() async {
    fixture = await DriftFacadeFixture.create(twoActivations: true);
    repository = fixture.repository;
    skill = fixture.managedSkillId;
    donor = await RemoteRevisionPackFixture.create(fixture);
    final draft = await driftSuccess(
      repository.ensureDraft(EnsureDraftRequest(managedSkillId: skill)),
    );
    await fixture.changeNotes(draft.path, 'Local notes\n');
    await driftSuccess(
      repository.publishDraft(PublishDraftRequest(managedSkillId: skill)),
    );
    local = (await _export(repository, fixture, 'local')).effective;
  });

  test('publishes a clean two-parent merge using the real ancestor', () async {
    expect((await inspectSelection()).effective, local);
    expect(local, isNot(donor.base.effective));
    final remoteUpstream = await donor.incoming(
      files: {'remote.md': 'first\n'},
    );
    final remote = await donor.incoming(
      parent: remoteUpstream.revision,
      files: {'remote.md': 'second\n'},
    );

    final applied = await driftSuccess(
      repository.applyRemoteState(
        RemoteSkillContent(
          managedSkillId: skill,
          expectedEffective: local,
          effective: remote.revision,
          upstream: remoteUpstream.revision,
          packPath: remote.packPath,
        ),
      ),
    );
    expect(applied, isA<RemoteApplyMerged>());
    final heads = await _export(repository, fixture, 'merged');
    expect(heads.effective, (applied as RemoteApplyMerged).newEffective);
    expect(heads.upstream, remoteUpstream.revision);
    final selection = await inspectSelection();
    expect(selection.effective, applied.newEffective);
    expect(selection.upstream, remoteUpstream.revision);
    await _expectParents(fixture, heads.effective, [local, remote.revision]);
    await fixture.expectEffectiveNotes('Local notes\n');
    await fixture.expectMaterializedNotes(
      'Local notes\n',
      secondActivation: true,
    );
    expect(
      await File(
        path.join(fixture.activationPath(), 'remote.md'),
      ).readAsString(),
      'second\n',
    );

    final revision = repository.snapshot.revision;
    expect(
      await driftSuccess(
        repository.applyRemoteState(
          RemoteSkillContent(
            managedSkillId: skill,
            expectedEffective: heads.effective,
            effective: remote.revision,
            upstream: remoteUpstream.revision,
          ),
        ),
      ),
      isA<RemoteApplyNoChange>(),
    );
    expect(repository.snapshot.revision, revision);
  });

  test(
    'keeps the descendant Upstream and then accepts a divergent Upstream',
    () async {
      final first = await donor.incoming(
        parent: local,
        files: {'first.md': 'one\n'},
      );
      final second = await donor.incoming(
        parent: first.revision,
        files: {'first.md': 'two\n'},
      );
      final other = await donor.incoming(files: {'other.md': 'three\n'});

      Future<RemoteApplyResult> apply(
        RevisionId expected,
        ({RevisionId revision, String packPath}) head,
        RevisionId upstream,
      ) => driftSuccess(
        repository.applyRemoteState(
          RemoteSkillContent(
            managedSkillId: skill,
            expectedEffective: expected,
            effective: head.revision,
            upstream: upstream,
            packPath: head.packPath,
          ),
        ),
      );

      expect(
        await apply(local, first, first.revision),
        isA<RemoteApplyFastForwarded>(),
      );
      expect(
        await apply(first.revision, second, donor.base.upstream!),
        isA<RemoteApplyFastForwarded>(),
      );
      expect(
        (await _export(repository, fixture, 'descendant')).upstream,
        first.revision,
      );

      expect(
        await apply(second.revision, other, other.revision),
        isA<RemoteApplyMerged>(),
      );
      expect(
        (await _export(repository, fixture, 'divergent')).upstream,
        other.revision,
      );
    },
  );

  test('an absent remote Upstream keeps a tracked local Upstream', () async {
    final before = await inspectSelection();
    expect(before.upstream, isNotNull);
    final remote = await donor.incoming(
      parent: local,
      files: {'remote.md': 'incoming'},
    );
    final applied = await driftSuccess(
      repository.applyRemoteState(
        RemoteSkillContent(
          managedSkillId: skill,
          expectedEffective: local,
          effective: remote.revision,
          packPath: remote.packPath,
        ),
      ),
    );
    expect(applied, isA<RemoteApplyFastForwarded>());
    final after = await inspectSelection();
    expect(after.effective, remote.revision);
    expect(after.upstream, before.upstream);
  });

  test('cancels before applying remote content', () async {
    final remote = await donor.incoming(
      parent: local,
      files: {'remote.md': 'remote'},
    );
    final before = repository.snapshot.revision;
    const historyRequest = OperationHistoryRequest();
    final historyBefore = await driftSuccess(
      repository.inspectOperationHistory(historyRequest),
    );
    final operation = repository.applyRemoteState(
      RemoteSkillContent(
        managedSkillId: skill,
        expectedEffective: local,
        effective: remote.revision,
        upstream: donor.base.upstream!,
        packPath: remote.packPath,
      ),
    );
    final cancel = operation.progress
        .firstWhere(
          (progress) => progress.phase == OperationProgressPhase.preparing,
        )
        .then((_) => operation.cancel());
    await cancel;
    await driftFailure(operation, SkillsErrorCode.operationCancelled);
    final history = await driftSuccess(
      repository.inspectOperationHistory(historyRequest),
    );
    expect(history.entries, hasLength(historyBefore.entries.length + 1));
    expect(
      history.entries
          .singleWhere((entry) => entry.operationId == operation.operationId)
          .status,
      OperationTerminalStatus.cancelled,
    );
    expect(repository.snapshot.revision, before);
    expect((await _export(repository, fixture, 'cancelled')).effective, local);
    await fixture.expectMaterializedNotes(
      'Local notes\n',
      secondActivation: true,
    );
  });

  test(
    'resumes a conflict after reopen and keeps the selected Upstream',
    () async {
      final remoteUpstream = await donor.incoming(
        files: {'remote.md': 'remote\n'},
      );
      final remote = await donor.incoming(
        parent: remoteUpstream.revision,
        files: {'notes.md': 'Remote notes\n'},
      );
      final request = RemoteSkillContent(
        managedSkillId: skill,
        expectedEffective: local,
        effective: remote.revision,
        upstream: remoteUpstream.revision,
        packPath: remote.packPath,
      );
      expect(
        await driftSuccess(repository.applyRemoteState(request)),
        isA<RemoteApplyConflicted>(),
      );
      expect((await inspectSelection()).effective, local);
      await fixture.expectEffectiveNotes('Local notes\n');
      expect(
        (await _export(repository, fixture, 'conflicted')).effective,
        local,
      );
      expect(
        await driftSuccess(repository.applyRemoteState(request)),
        isA<RemoteApplyDraftResolutionRequired>(),
      );
      for (final target in [local, donor.base.effective]) {
        expect(
          await driftSuccess(
            repository.applyRemoteState(
              RemoteSkillContent(
                managedSkillId: skill,
                expectedEffective: local,
                effective: target,
                upstream: donor.base.upstream!,
              ),
            ),
          ),
          isA<RemoteApplyNoChange>(),
        );
      }

      await driftSuccess(repository.close());
      repository = fixture.createRepository();
      await driftSuccess(repository.open());
      final conflict = await driftSuccess(
        repository.inspectUpdateCandidate(
          InspectUpdateCandidateRequest(managedSkillId: skill),
        ),
      );
      expect(conflict?.status, UpdateCandidateStatus.conflicted);
      expect(conflict?.conflicts.single.path, 'notes.md');
      final draft = await driftSuccess(
        repository.inspectDraft(InspectDraftRequest(managedSkillId: skill)),
      );
      await fixture.changeNotes(draft!.path, 'Resolved notes\n');
      await driftSuccess(
        repository.resolveUpdateConflict(
          ResolveUpdateConflictRequest(
            managedSkillId: skill,
            path: 'notes.md',
            resolutionState: UpdateConflictResolutionState.resolved,
          ),
        ),
      );
      await driftSuccess(
        repository.publishUpdateCandidate(
          PublishUpdateCandidateRequest(managedSkillId: skill),
        ),
      );

      final heads = await _export(repository, fixture, 'resolved');
      expect(heads.upstream, remoteUpstream.revision);
      await _expectParents(fixture, heads.effective, [local, remote.revision]);
      await fixture.expectMaterializedNotes(
        'Resolved notes\n',
        secondActivation: true,
      );
    },
  );

  for (final side in UpdateCandidateSide.values) {
    test('resolves reviewed Sync Merge content using ${side.name}', () async {
      final remote = await donor.incoming(
        files: {'notes.md': 'Remote notes\n', 'incoming.md': 'New file\n'},
      );
      expect(
        await driftSuccess(
          repository.applyRemoteState(
            RemoteSkillContent(
              managedSkillId: skill,
              expectedEffective: local,
              effective: remote.revision,
              upstream: donor.base.upstream,
              packPath: remote.packPath,
            ),
          ),
        ),
        isA<RemoteApplyConflicted>(),
      );
      final draft = (await driftSuccess(
        repository.inspectDraft(InspectDraftRequest(managedSkillId: skill)),
      ))!;
      final stale = (await driftSuccess(
        repository.inspectUpdateCandidateResolution(skill),
      ))!;
      await File(
        path.join(draft.path, 'custom.md'),
      ).writeAsString('My draft\n');
      final empty = await Directory(path.join(draft.path, 'empty')).create();
      SkillsOperation<RepositorySnapshot> resolve(Object token) =>
          repository.resolveUpdateCandidateConflicts(
            ResolveUpdateCandidateConflictsRequest(
              managedSkillId: skill,
              reviewToken: token,
              side: side,
            ),
          );
      final revision = repository.snapshot.revision;
      expect(
        (await resolve(Object()).completed).failureOrNull?.code,
        SkillsErrorCode.staleSnapshot,
      );
      expect(
        (await resolve(stale.token).completed).failureOrNull?.code,
        SkillsErrorCode.staleSnapshot,
      );
      expect(repository.snapshot.revision, revision);
      expect(
        await File(path.join(draft.path, 'custom.md')).readAsString(),
        'My draft\n',
      );
      expect(await empty.exists(), isTrue);
      final fresh = (await driftSuccess(
        repository.inspectUpdateCandidateResolution(skill),
      ))!;
      final expected = side == UpdateCandidateSide.current
          ? 'Local notes\n'
          : 'Remote notes\n';
      final resolved = await driftSuccess(resolve(fresh.token));
      expect(
        resolved
            .findSkill(skill)
            ?.updateCandidate
            ?.conflicts
            .single
            .resolutionState,
        UpdateConflictResolutionState.resolved,
      );
      expect(
        await File(path.join(draft.path, 'notes.md')).readAsString(),
        expected,
      );
      expect(
        await File(path.join(draft.path, 'incoming.md')).readAsString(),
        'New file\n',
      );
      expect(
        await File(path.join(draft.path, 'custom.md')).readAsString(),
        'My draft\n',
      );
      await fixture.expectMaterializedNotes(
        'Local notes\n',
        secondActivation: true,
      );

      await driftSuccess(
        repository.publishUpdateCandidate(
          PublishUpdateCandidateRequest(managedSkillId: skill),
        ),
      );
      await fixture.expectMaterializedNotes(expected, secondActivation: true);
      await _expectParents(fixture, (await inspectSelection()).effective, [
        local,
        remote.revision,
      ]);
    });
  }

  for (final committed in [false, true]) {
    test(
      'recovers a side selection interrupted ${committed ? 'after' : 'before'} commit',
      () async {
        final remote = await donor.incoming(
          files: {'notes.md': 'Remote notes\n'},
        );
        expect(
          await driftSuccess(
            repository.applyRemoteState(
              RemoteSkillContent(
                managedSkillId: skill,
                expectedEffective: local,
                effective: remote.revision,
                upstream: donor.base.upstream,
                packPath: remote.packPath,
              ),
            ),
          ),
          isA<RemoteApplyConflicted>(),
        );
        final draft = (await driftSuccess(
          repository.inspectDraft(InspectDraftRequest(managedSkillId: skill)),
        ))!;
        final notes = File(path.join(draft.path, 'notes.md'));
        final before = await notes.readAsString();
        final previousRevision = repository.snapshot.revision.value;
        await driftSuccess(repository.close());
        final layout = WorkspaceLayout(fixture.workspacePath);
        final operation = OperationId('123e4567-e89b-42d3-a456-426614174097');
        await crashRemoteApply([
          layout.rootPath,
          'resolve',
          skill.value,
          operation.value,
        ], committed: committed);
        final interrupted = readOperationDatabaseRows(layout.databasePath);
        expect(
          interrupted['operation_journals']!.singleWhere(
            (row) => row['operation_id'] == operation.value,
          )['phase'],
          committed ? 'committed' : 'applying',
        );
        repository = fixture.createRepository();
        await driftSuccess(repository.open());
        expect(
          repository.snapshot.revision.value,
          previousRevision + (committed ? 1 : 0),
        );
        expect(
          await notes.readAsString(),
          committed ? 'Remote notes\n' : before,
        );
        final candidate = repository.snapshot.findSkill(skill)?.updateCandidate;
        expect(
          candidate?.conflicts.single.resolutionState,
          committed
              ? UpdateConflictResolutionState.resolved
              : UpdateConflictResolutionState.unresolved,
        );
        expect(
          await Directory(layout.operationRecoveryPath(operation)).exists(),
          isFalse,
        );
        expect(
          await Directory(layout.operationStagingPath(operation)).exists(),
          isFalse,
        );
        await fixture.expectMaterializedNotes(
          'Local notes\n',
          secondActivation: true,
        );
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  }

  test(
    'keeps the incoming rename, delete, binary bytes, and executable mode',
    () async {
      final base = await donor.incoming(
        parent: local,
        files: {
          'move.md': 'Shared content used to detect the same rename\n',
          'delete.md': 'Shared content\n',
          'both.bin': '\u0000base',
          'script.sh': 'base\n',
          'preserved.md': 'Base conflict\n',
        },
      );
      expect(
        await driftSuccess(
          repository.applyRemoteState(
            RemoteSkillContent(
              managedSkillId: skill,
              expectedEffective: local,
              effective: base.revision,
              upstream: donor.base.upstream,
              packPath: base.packPath,
            ),
          ),
        ),
        isA<RemoteApplyFastForwarded>(),
      );
      final localDraft = await driftSuccess(
        repository.ensureDraft(EnsureDraftRequest(managedSkillId: skill)),
      );
      File file(String name) => File(path.join(localDraft.path, name));
      await file('move.md').rename(file('local-name.md').path);
      await file('delete.md').writeAsString('Local content\n');
      await file('both.bin').writeAsBytes([0, 1, 2]);
      await file('script.sh').writeAsString('Local script\n');
      await file('preserved.md').writeAsString('Local conflict\n');
      await driftSuccess(
        repository.publishDraft(PublishDraftRequest(managedSkillId: skill)),
      );
      final before = (await inspectSelection()).effective;
      final remote = await donor.incoming(
        parent: base.revision,
        deletedFiles: {'move.md', 'delete.md'},
        executableFiles: {'script.sh'},
        files: {
          'remote-name.md': 'Shared content used to detect the same rename\n',
          'both.bin': '\u0000remote',
          'script.sh': 'Remote script\n',
          'preserved.md': 'Remote conflict\n',
        },
      );
      expect(
        await driftSuccess(
          repository.applyRemoteState(
            RemoteSkillContent(
              managedSkillId: skill,
              expectedEffective: before,
              effective: remote.revision,
              upstream: donor.base.upstream,
              packPath: remote.packPath,
            ),
          ),
        ),
        isA<RemoteApplyConflicted>(),
      );
      final stale = (await driftSuccess(
        repository.inspectUpdateCandidateResolution(skill),
      ))!;
      final conflictPaths = stale.summary.conflicts
          .map((item) => item.path)
          .toList();
      expect(
        conflictPaths,
        containsAll(['both.bin', 'delete.md', 'script.sh', 'preserved.md']),
      );
      expect(conflictPaths.any((name) => name.contains('name.md')), isTrue);
      await file('preserved.md').writeAsString('Already resolved\n');
      await driftSuccess(
        repository.resolveUpdateConflict(
          ResolveUpdateConflictRequest(
            managedSkillId: skill,
            path: 'preserved.md',
            resolutionState: UpdateConflictResolutionState.resolved,
          ),
        ),
      );
      SkillsOperation<RepositorySnapshot> resolve(Object token) =>
          repository.resolveUpdateCandidateConflicts(
            ResolveUpdateCandidateConflictsRequest(
              managedSkillId: skill,
              reviewToken: token,
              side: UpdateCandidateSide.incoming,
            ),
          );
      expect(
        (await resolve(stale.token).completed).failureOrNull?.code,
        SkillsErrorCode.staleSnapshot,
      );
      final review = (await driftSuccess(
        repository.inspectUpdateCandidateResolution(skill),
      ))!;
      await driftSuccess(resolve(review.token));
      expect(await file('local-name.md').exists(), isFalse);
      expect(
        await file('remote-name.md').readAsString(),
        startsWith('Shared content'),
      );
      expect(await file('delete.md').exists(), isFalse);
      expect(await file('both.bin').readAsBytes(), '\u0000remote'.codeUnits);
      expect(await file('preserved.md').readAsString(), 'Already resolved\n');
      expect(await file('script.sh').readAsString(), 'Remote script\n');
      await driftSuccess(
        repository.publishUpdateCandidate(
          PublishUpdateCandidateRequest(managedSkillId: skill),
        ),
      );
      final selected = await inspectSelection();
      final store = WorkspaceLayout(
        fixture.workspacePath,
      ).revisionStorePath(skill);
      final mode = await Process.run('git', [
        '--git-dir=$store',
        'ls-tree',
        selected.effective.value,
        'script.sh',
      ]);
      expect(mode.exitCode, 0);
      expect(mode.stdout, startsWith('100755 '));
      await _expectParents(fixture, selected.effective, [
        before,
        remote.revision,
      ]);
    },
  );

  test(
    'reviews a pending pack without applying it over a Dirty Draft',
    () async {
      final draft = (await driftSuccess(
        repository.ensureDraft(EnsureDraftRequest(managedSkillId: skill)),
      ));
      await fixture.changeNotes(draft.path, 'Unpublished\n');
      final remote = await donor.incoming(
        files: {'renamed.md': 'Local notes\n', 'new.bin': '\u0000bin'},
        parent: local,
        deletedFiles: {'notes.md'},
      );
      final before = repository.snapshot.revision;
      final operation = repository.inspectRevisionPackDiff(
        InspectRevisionPackDiffRequest(
          managedSkillId: skill,
          expectedEffective: local,
          incomingEffective: remote.revision,
          packPath: remote.packPath,
        ),
      );
      final diff = await driftSuccess(operation);
      expect(diff.from, local);
      expect(diff.to, remote.revision);
      final files = {for (final file in diff.files) file.path: file};
      expect(files['renamed.md']?.previousPath, 'notes.md');
      expect(files['new.bin']?.isBinary, isTrue);
      expect(repository.snapshot.revision, before);
      await fixture.expectMaterializedNotes(
        'Local notes\n',
        secondActivation: true,
      );
      expect(
        await File(path.join(draft.path, 'notes.md')).readAsString(),
        'Unpublished\n',
      );
      final layout = WorkspaceLayout(fixture.workspacePath);
      expect(
        await Directory(
          layout.operationStagingPath(operation.operationId),
        ).exists(),
        isFalse,
      );
      final store = layout.revisionStorePath(skill);
      final landed = await Process.run('git', [
        '--git-dir=$store',
        'cat-file',
        '-e',
        remote.revision.value,
      ]);
      expect(landed.exitCode, isNot(0));
      expect(
        (await repository
                .inspectRevisionPackDiff(
                  InspectRevisionPackDiffRequest(
                    managedSkillId: skill,
                    expectedEffective: donor.base.effective,
                    incomingEffective: remote.revision,
                    packPath: remote.packPath,
                  ),
                )
                .completed)
            .failureOrNull
            ?.code,
        SkillsErrorCode.staleSnapshot,
      );
      final malformed = await File(
        path.join(fixture.exportDirectory, 'malformed.pack'),
      ).writeAsString('fixture');
      expect(
        (await repository
                .inspectRevisionPackDiff(
                  InspectRevisionPackDiffRequest(
                    managedSkillId: skill,
                    expectedEffective: local,
                    incomingEffective: remote.revision,
                    packPath: malformed.path,
                  ),
                )
                .completed)
            .failureOrNull
            ?.code,
        SkillsErrorCode.archiveInvalid,
      );
      final cancelled = repository.inspectRevisionPackDiff(
        InspectRevisionPackDiffRequest(
          managedSkillId: skill,
          expectedEffective: local,
          incomingEffective: remote.revision,
          packPath: remote.packPath,
        ),
      );
      await cancelled.progress
          .firstWhere(
            (event) => event.phase == OperationProgressPhase.preparing,
          )
          .then((_) => cancelled.cancel());
      expect(
        (await cancelled.completed).failureOrNull?.code,
        SkillsErrorCode.operationCancelled,
      );
      expect(
        await Directory(
          layout.operationStagingPath(cancelled.operationId),
        ).exists(),
        isFalse,
      );
      expect(repository.snapshot.revision, before);
    },
  );
}

Future<RevisionPackExport> _export(
  SkillsRepository repository,
  DriftFacadeFixture fixture,
  String name,
) => driftSuccess(
  repository.exportRevisionPack(
    ExportRevisionPackRequest(
      managedSkillId: fixture.managedSkillId,
      destinationPath: path.join(fixture.exportDirectory, '$name.pack'),
    ),
  ),
);

Future<void> _expectParents(
  DriftFacadeFixture fixture,
  RevisionId commit,
  List<RevisionId> parents,
) async {
  final store = WorkspaceLayout(
    fixture.workspacePath,
  ).revisionStorePath(fixture.managedSkillId);
  final result = await Process.run('git', [
    '--git-dir=$store',
    'show',
    '-s',
    '--format=%P',
    commit.value,
  ]);
  expect(result.exitCode, 0);
  expect(
    (result.stdout as String).trim().split(' '),
    parents.map((id) => id.value),
  );
}
