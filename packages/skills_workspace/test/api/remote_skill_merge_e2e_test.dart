import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:skills_workspace/skills_workspace.dart';
import 'package:skills_workspace/src/infrastructure/workspace_layout.dart';
import 'package:test/test.dart';

import '../support/drift_facade_fixture.dart';
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
