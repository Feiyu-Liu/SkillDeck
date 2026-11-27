import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:skills_workspace/skills_workspace.dart';
import 'package:skills_workspace/src/infrastructure/workspace_layout.dart';
import 'package:test/test.dart';
import '../support/drift_facade_fixture.dart';
import '../support/remote_revision_pack_fixture.dart';
import '../support/operations/remote_apply_test_support.dart';

void main() {
  late DriftFacadeFixture fixture, donor;
  late SkillsRepository repository;
  late ManagedSkillId id;
  late RemoteRevisionPackFixture incoming;
  late String pack;
  final source = GitSourceDescriptor(
    locator: 'https://github.com/test/replacement.git',
  );
  Future<RevisionSelection> selection() async => (await driftSuccess(
    repository.inspectRevisionSelections(
      InspectRevisionSelectionsRequest(managedSkillIds: {id}),
    ),
  )).selections[id]!;
  Future<RemoteSkillSourceReplacement> request({
    RevisionId? expected,
    String? expectedSourceEpoch,
    RevisionId? effective,
    RevisionId? upstream,
    String? packPath,
    SourceDescriptor? provenance,
  }) async => RemoteSkillSourceReplacement(
    managedSkillId: id,
    expectedEffective: expected ?? (await selection()).effective,
    expectedSourceEpoch: expectedSourceEpoch,
    packPath: packPath ?? pack,
    effective: effective ?? incoming.base.effective,
    upstream: upstream ?? incoming.base.upstream,
    source: provenance ?? source,
  );
  setUp(() async {
    fixture = await DriftFacadeFixture.create(twoActivations: true);
    repository = fixture.repository;
    id = fixture.managedSkillId;
    donor = await DriftFacadeFixture.create(activate: false);
    final draft = await driftSuccess(
      donor.repository.ensureDraft(
        EnsureDraftRequest(managedSkillId: donor.managedSkillId),
      ),
    );
    await donor.changeNotes(draft.path, 'replacement content\n');
    await driftSuccess(
      donor.repository.publishDraft(
        PublishDraftRequest(managedSkillId: donor.managedSkillId),
      ),
    );
    incoming = await RemoteRevisionPackFixture.create(donor);
    pack = path.join(donor.exportDirectory, 'base.pack');
  });
  test(
    'identical-head replacement stales a previously reviewed apply or removal',
    () async {
      await driftSuccess(repository.applyRemoteState(await request()));
      final reviewed = await selection();
      expect(reviewed.sourceEpoch, isNotNull);
      await driftSuccess(
        repository.applyRemoteState(
          await request(expectedSourceEpoch: reviewed.sourceEpoch),
        ),
      );
      final fresh = await selection();
      expect(fresh.effective, reviewed.effective);
      expect(fresh.sourceEpoch, isNot(reviewed.sourceEpoch));
      final layout = WorkspaceLayout(fixture.workspacePath);
      final rows = readOperationDatabaseRows(layout.databasePath);
      final snapshot = repository.snapshot;
      for (final stale in [
        RemoteSkillContent(
          managedSkillId: id,
          expectedEffective: reviewed.effective,
          expectedSourceEpoch: reviewed.sourceEpoch,
          effective: fresh.effective,
          upstream: fresh.upstream,
          packPath: pack,
        ),
        RemoteSkillRemoval(
          managedSkillId: id,
          expectedEffective: reviewed.effective,
          expectedSourceEpoch: reviewed.sourceEpoch,
        ),
      ]) {
        await driftFailure(
          repository.applyRemoteState(stale),
          SkillsErrorCode.staleSnapshot,
          reason: 'sourceLineageChanged',
        );
        expect(repository.snapshot.revision, snapshot.revision);
        expect(repository.snapshot.findSkill(id), snapshot.findSkill(id));
        expect(readOperationDatabaseRows(layout.databasePath), rows);
      }
    },
  );
  test(
    'preserves identity, activations and extra data while selecting unrelated full history',
    () async {
      final tag = await driftSuccess(
        repository.createPersonalTag(CreatePersonalTagRequest(name: 'Work')),
      );
      final old = (await selection()).effective;
      await driftSuccess(
        repository.applyRemoteState(
          RemoteSkillMetadata(
            managedSkillId: id,
            expectedEffective: old,
            favorite: true,
            note: 'keep note',
            tagIds: {tag.id},
          ),
        ),
      );
      final before = repository.snapshot.findSkill(id)!,
          revision = repository.snapshot.revision;
      expect(
        await driftSuccess(repository.applyRemoteState(await request())),
        isA<RemoteApplySourceReplaced>(),
      );
      final after = repository.snapshot.findSkill(id)!;
      expect(after.source, source);
      expect(after.activations, before.activations);
      expect(after.favorite, before.favorite);
      expect(after.note, before.note);
      expect(after.personalTagIds, before.personalTagIds);
      final heads = await selection();
      expect(heads.effective, incoming.base.effective);
      expect(heads.upstream, incoming.base.upstream);
      for (final root in [
        fixture.repositoryCopyPath,
        fixture.activationPath(),
        fixture.activationPath(DriftFacadeFixture.secondAgentId),
      ]) {
        expect(
          await File(path.join(root, 'notes.md')).readAsString(),
          'replacement content\n',
        );
      }
      final exported = await driftSuccess(
        repository.exportRevisionPack(
          ExportRevisionPackRequest(
            managedSkillId: id,
            destinationPath: path.join(
              fixture.exportDirectory,
              'replaced.pack',
            ),
          ),
        ),
      );
      expect(exported.effective, incoming.base.effective);
      final feed =
          await driftSuccess(
                repository.inspectCommittedChanges(
                  InspectCommittedChangesRequest(since: revision),
                ),
              )
              as CommittedChangesAvailable;
      expect(feed.entries.single.managedSkillId, id);
      expect(feed.entries.single.kinds, contains(CommittedChangeKind.content));
      final rows = readOperationDatabaseRows(
        WorkspaceLayout(fixture.workspacePath).databasePath,
      );
      expect(rows['source_lineages'], hasLength(1));
      // A new local publish makes a later replacement a Git-to-Git history reset.
      final draft = await driftSuccess(
        repository.ensureDraft(EnsureDraftRequest(managedSkillId: id)),
      );
      await fixture.changeNotes(draft.path, 'private local history\n');
      await driftSuccess(
        repository.publishDraft(PublishDraftRequest(managedSkillId: id)),
      );
      final privateHead = (await selection()).effective;
      expect(
        await driftSuccess(
          repository.applyRemoteState(
            await request(
              provenance: GitSourceDescriptor(
                locator: 'https://github.com/test/second.git',
              ),
            ),
          ),
        ),
        isA<RemoteApplySourceReplaced>(),
      );
      final oldObject = await Process.run('git', [
        '--git-dir=${WorkspaceLayout(fixture.workspacePath).revisionStorePath(id)}',
        'cat-file',
        '-e',
        privateHead.value,
      ]);
      expect(oldObject.exitCode, isNot(0));
      expect((await selection()).effective, isNot(old));
    },
  );
  test(
    'guards, exact retry, dirty Draft and malformed pack leave no Operation Record or business change',
    () async {
      final layout = WorkspaceLayout(fixture.workspacePath);
      final draft = await driftSuccess(
        repository.ensureDraft(EnsureDraftRequest(managedSkillId: id)),
      );
      await fixture.changeNotes(draft.path, 'dirty\n');
      var rows = readOperationDatabaseRows(layout.databasePath),
          before = repository.snapshot;
      await driftFailure(
        repository.applyRemoteState(
          await request(expected: RevisionId('0' * 40)),
        ),
        SkillsErrorCode.staleSnapshot,
        reason: 'effectiveRevisionChanged',
      );
      expect(readOperationDatabaseRows(layout.databasePath), rows);
      expect(
        await driftSuccess(repository.applyRemoteState(await request())),
        isA<RemoteApplyDraftResolutionRequired>(),
      );
      expect(readOperationDatabaseRows(layout.databasePath), rows);
      expect(repository.snapshot, before);
      await driftSuccess(
        repository.publishDraft(PublishDraftRequest(managedSkillId: id)),
      );
      final malformed = File(path.join(fixture.exportDirectory, 'bad.pack'));
      await malformed.writeAsString('not a pack');
      rows = readOperationDatabaseRows(layout.databasePath);
      await driftFailure(
        repository.applyRemoteState(await request(packPath: malformed.path)),
        SkillsErrorCode.archiveInvalid,
        reason: 'packMalformed',
      );
      expect(readOperationDatabaseRows(layout.databasePath), rows);
      await driftSuccess(repository.applyRemoteState(await request()));
      rows = readOperationDatabaseRows(layout.databasePath);
      before = repository.snapshot;
      expect(
        await driftSuccess(
          repository.applyRemoteState(await request(packPath: malformed.path)),
        ),
        isA<RemoteApplyNoChange>(),
      );
      expect(readOperationDatabaseRows(layout.databasePath), rows);
      expect(repository.snapshot, before);
      final absent = RemoteSkillSourceReplacement(
        managedSkillId: ManagedSkillId('00000000-0000-4000-8000-000000000001'),
        expectedEffective: (await selection()).effective,
        packPath: pack,
        effective: incoming.base.effective,
        upstream: incoming.base.upstream,
        source: source,
      );
      await driftFailure(
        repository.applyRemoteState(absent),
        SkillsErrorCode.skillNotFound,
      );
      expect(readOperationDatabaseRows(layout.databasePath), rows);
      final fork = await RemoteRevisionPackFixture.create(fixture);
      final localDraft = await driftSuccess(
        repository.ensureDraft(EnsureDraftRequest(managedSkillId: id)),
      );
      await fixture.changeNotes(localDraft.path, 'local conflict\n');
      await driftSuccess(
        repository.publishDraft(PublishDraftRequest(managedSkillId: id)),
      );
      final remote = fork.incoming(files: {'notes.md': 'remote conflict\n'});
      final changed = await remote;
      expect(
        await driftSuccess(
          repository.applyRemoteState(
            RemoteSkillContent(
              managedSkillId: id,
              expectedEffective: (await selection()).effective,
              effective: changed.revision,
              upstream: fork.base.upstream,
              packPath: changed.packPath,
            ),
          ),
        ),
        isA<RemoteApplyConflicted>(),
      );
      rows = readOperationDatabaseRows(layout.databasePath);
      expect(
        await driftSuccess(repository.applyRemoteState(await request())),
        isA<RemoteApplyDraftResolutionRequired>(),
      );
      expect(readOperationDatabaseRows(layout.databasePath), rows);
    },
  );
  test(
    'slot relocation keeps activations and refuses an occupied name',
    () async {
      final changed = await incoming.incoming(
        files: {
          'SKILL.md':
              '---\nname: relocated\ndescription: Remote replacement\n---\n',
        },
      );
      final otherDir = Directory(
        path.join(fixture.temporaryRoot.path, 'occupied'),
      );
      await otherDir.create();
      await fixture.writeSkillMarkdown(otherDir.path, name: 'relocated');
      final installed =
          await driftSuccess(
                repository.install(
                  InstallRequest(
                    source: LocalSourceDescriptor(locator: otherDir.path),
                    activationSelection: const ActivationSelection.none(),
                  ),
                ),
              )
              as InstallCompleted;
      final occupant = installed.report.affectedSkillIds.single;
      final replacement = await request(
        packPath: changed.packPath,
        effective: changed.revision,
      );
      final rows = readOperationDatabaseRows(
        WorkspaceLayout(fixture.workspacePath).databasePath,
      );
      final result =
          await driftSuccess(repository.applyRemoteState(replacement))
              as RemoteApplySkillSlotOccupied;
      expect(result.occupant, occupant);
      expect(
        readOperationDatabaseRows(
          WorkspaceLayout(fixture.workspacePath).databasePath,
        ),
        rows,
      );
      final selected = (await driftSuccess(
        repository.inspectRevisionSelections(
          InspectRevisionSelectionsRequest(managedSkillIds: {occupant}),
        ),
      )).selections[occupant]!;
      await driftSuccess(
        repository.applyRemoteState(
          RemoteSkillRemoval(
            managedSkillId: occupant,
            expectedEffective: selected.effective,
          ),
        ),
      );
      expect(
        await driftSuccess(
          repository.applyRemoteState(
            await request(
              packPath: changed.packPath,
              effective: changed.revision,
            ),
          ),
        ),
        isA<RemoteApplySourceReplaced>(),
      );
      expect(repository.snapshot.findSkill(id)!.declaredName, 'relocated');
      expect(await Directory(fixture.repositoryCopyPath).exists(), isFalse);
      for (final root in [
        WorkspaceLayout(fixture.workspacePath).repositoryCopiesRoot,
        fixture.activationRoot(),
        fixture.activationRoot(DriftFacadeFixture.secondAgentId),
      ]) {
        expect(await Directory(path.join(root, 'relocated')).exists(), isTrue);
      }
    },
  );
  test(
    'Synced Origin accepts both allowed upstream shapes and rejects every constructor mismatch',
    () async {
      final local = SyncedOriginSourceDescriptor(
        originSourceType: SyncedOriginSourceType.local,
        originDeviceLabel: 'Donor',
        displayLabel: 'folder',
      );
      expect(
        await driftSuccess(
          repository.applyRemoteState(await request(provenance: local)),
        ),
        isA<RemoteApplySourceReplaced>(),
      );
      final adopted = SyncedOriginSourceDescriptor(
        originSourceType: SyncedOriginSourceType.adoptedSnapshot,
        originDeviceLabel: 'Donor',
        displayLabel: 'snapshot',
      );
      final expected = (await selection()).effective;
      RemoteSkillSourceReplacement make(
        SourceDescriptor s,
        RevisionId? upstream,
      ) => RemoteSkillSourceReplacement(
        managedSkillId: id,
        expectedEffective: expected,
        packPath: pack,
        effective: incoming.base.effective,
        upstream: upstream,
        source: s,
      );
      for (final s in [
        source,
        WellKnownSourceDescriptor(locator: 'https://example.com/skills.json'),
        local,
      ]) {
        expect(() => make(s, null), throwsArgumentError);
      }
      expect(() => make(adopted, incoming.base.upstream), throwsArgumentError);
      expect(
        () => make(
          LocalSourceDescriptor(locator: fixture.sourcePath),
          incoming.base.upstream,
        ),
        throwsArgumentError,
      );
      expect(
        () => make(
          AdoptedSnapshotSourceDescriptor(
            authoritativeLocation: fixture.sourcePath,
            contentHash: 'a' * 64,
          ),
          null,
        ),
        throwsArgumentError,
      );
      expect(
        await driftSuccess(repository.applyRemoteState(make(adopted, null))),
        isA<RemoteApplySourceReplaced>(),
      );
      expect((await selection()).upstream, isNull);
    },
  );
  for (final committed in [false, true]) {
    test(
      'interruption ${committed ? 'after' : 'before'} commit recovers the entire replacement',
      () async {
        final expected = (await selection()).effective;
        final operation = OperationId('00000000-0000-4000-8000-000000000025');
        await driftSuccess(repository.close());
        await crashRemoteApply([
          fixture.workspacePath,
          'replace',
          id.value,
          expected.value,
          pack,
          incoming.base.effective.value,
          incoming.base.upstream!.value,
          operation.value,
        ], committed: committed);
        repository = fixture.createRepository();
        await driftSuccess(repository.open());
        expect(
          (await selection()).effective,
          committed ? incoming.base.effective : expected,
        );
        expect(repository.snapshot.findSkill(id)!.activations, hasLength(2));
        expect(
          await File(
            path.join(fixture.repositoryCopyPath, 'notes.md'),
          ).readAsString(),
          committed ? 'replacement content\n' : DriftFacadeFixture.baseNotes,
        );
      },
    );
  }
}
