import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:skills_workspace/skills_workspace.dart';
import 'package:skills_workspace/src/infrastructure/workspace_layout.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import '../support/drift_facade_fixture.dart';

void main() {
  late DriftFacadeFixture donor;
  late String receivingRoot;
  late String agentSkills;
  late SkillsRepositoryConfiguration receiverConfiguration;
  late SkillsRepository receiver;

  setUp(() async {
    donor = await DriftFacadeFixture.create(activate: false);
    receivingRoot = path.join(donor.temporaryRoot.path, 'receiver');
    final home = path.join(receivingRoot, 'home');
    agentSkills = path.join(home, '.claude', 'skills');
    await Directory(agentSkills).create(recursive: true);
    receiverConfiguration = SkillsRepositoryConfiguration(
      rootPath: path.join(receivingRoot, 'workspace'),
      agentHomePath: home,
    );
    receiver = createSkillsRepository(receiverConfiguration);
    addTearDown(() async {
      if (receiver.isOpen) await driftSuccess(receiver.close());
    });
    await driftSuccess(receiver.open());
  });

  String packPath(String name) =>
      path.join(donor.exportDirectory, '$name.pack');

  File copiedNotes([String slot = DriftFacadeFixture.skillName]) => File(
    path.join(
      receivingRoot,
      'workspace',
      'repository-copies',
      slot,
      'notes.md',
    ),
  );

  Future<RevisionPackExport> export(
    SkillsRepository repository,
    ManagedSkillId id,
    String name,
  ) => driftSuccess(
    repository.exportRevisionPack(
      ExportRevisionPackRequest(
        managedSkillId: id,
        destinationPath: packPath(name),
      ),
    ),
  );

  Future<RevisionSelection> selection(ManagedSkillId id) async =>
      (await driftSuccess(
        receiver.inspectRevisionSelections(
          InspectRevisionSelectionsRequest(managedSkillIds: {id}),
        ),
      )).selections[id]!;

  Future<CommittedChangesAvailable> feed(RepositoryRevision since) async =>
      await driftSuccess(
            receiver.inspectCommittedChanges(
              InspectCommittedChangesRequest(since: since),
            ),
          )
          as CommittedChangesAvailable;

  Future<List<OperationId>> operationHistory() async => [
    for (final entry in (await driftSuccess(
      receiver.inspectOperationHistory(const OperationHistoryRequest()),
    )).entries)
      entry.operationId,
  ];

  Future<void> publishNotes(
    SkillsRepository repository,
    ManagedSkillId id,
    String notes,
  ) async {
    final draft = await driftSuccess(
      repository.ensureDraft(EnsureDraftRequest(managedSkillId: id)),
    );
    await donor.changeNotes(draft.path, notes);
    await driftSuccess(
      repository.publishDraft(PublishDraftRequest(managedSkillId: id)),
    );
  }

  Future<RemoteSkillInstall> fromDonor(SourceDescriptor source) async {
    final heads = await export(donor.repository, donor.managedSkillId, 'donor');
    return RemoteSkillInstall(
      packPath: packPath('donor'),
      effective: heads.effective,
      upstream: heads.upstream,
      source: source,
    );
  }

  Future<ManagedSkillId> install(RemoteSkillInstall request) async {
    final result = await driftSuccess(receiver.applyRemoteState(request));
    expect(result, isA<RemoteApplyInstalled>());
    return (result as RemoteApplyInstalled).managedSkillId;
  }

  test(
    'installs distinct heads, preserves Git provenance and history, and emits content',
    () async {
      await publishNotes(
        donor.repository,
        donor.managedSkillId,
        'first publication\n',
      );
      final earlier = await export(
        donor.repository,
        donor.managedSkillId,
        'earlier',
      );
      await publishNotes(
        donor.repository,
        donor.managedSkillId,
        'latest publication\n',
      );
      final source = GitSourceDescriptor(
        locator: 'https://example.invalid/team/skills.git',
        ref: 'stable',
        repositorySubpath: 'library',
        skillPath: 'nested/drift-skill',
      );
      final request = await fromDonor(source);
      expect(request.effective, isNot(request.upstream));
      final before = receiver.snapshot.revision;

      final id = await install(request);

      final installed = receiver.snapshot.managedSkills.single;
      expect(installed.id, id);
      expect(installed.slotKey, DriftFacadeFixture.skillName);
      expect(installed.declaredName, DriftFacadeFixture.skillName);
      expect(installed.displayName, DriftFacadeFixture.skillName);
      expect(installed.description, 'Drift facade test');
      expect(installed.source, source);
      expect(installed.activations, isEmpty);
      expect(installed.draft, isNull);
      expect(await copiedNotes().readAsString(), 'latest publication\n');
      expect(await Directory(agentSkills).list().isEmpty, isTrue);
      final selected = await selection(id);
      expect(selected.effective, request.effective);
      expect(selected.upstream, request.upstream);

      final changeFeed = await feed(before);
      expect(changeFeed.current.value, before.value + 1);
      expect(changeFeed.current, receiver.snapshot.revision);
      expect(changeFeed.entries.single.managedSkillId, id);
      expect(changeFeed.entries.single.revision, changeFeed.current);
      expect(changeFeed.entries.single.kinds, {CommittedChangeKind.content});
      expect(changeFeed.vocabularyChanged, isFalse);

      Future<void> expectPackedHistory(String name) async {
        final reExported = await export(receiver, id, name);
        expect(reExported.effective, request.effective);
        expect(reExported.upstream, request.upstream);
        final fresh = path.join(receivingRoot, '$name.git');
        await _git(['init', '--bare', '--object-format=sha1', fresh]);
        final pack = path.join(fresh, 'objects', 'pack', '$name.pack');
        await File(packPath(name)).copy(pack);
        await _git(['-C', fresh, 'index-pack', '--strict', pack]);
        expect(
          (await _git([
            '-C',
            fresh,
            'rev-list',
            reExported.effective.value,
          ])).trim().split('\n'),
          [
            reExported.effective.value,
            earlier.effective.value,
            reExported.upstream!.value,
          ],
        );
        expect(
          await _git([
            '-C',
            fresh,
            'show',
            '${earlier.effective.value}:notes.md',
          ]),
          'first publication\n',
        );
      }

      await expectPackedHistory('re-exported');

      await driftSuccess(receiver.close());
      final layout = WorkspaceLayout(receiverConfiguration.rootPath);
      final storePath = layout.revisionStorePath(id);
      await Directory(
        storePath,
      ).rename(path.join(receivingRoot, 'removed.git'));
      receiver = createSkillsRepository(receiverConfiguration);
      final recovered = await driftSuccess(receiver.open());
      expect(recovered.integrity.skills.single.managedSkillId, id);
      expect(
        recovered.integrity.skills.single.status,
        SkillIntegrityStatus.recovered,
      );
      expect(await Directory(storePath).exists(), isTrue);
      await expectPackedHistory('recovered');
    },
  );

  test(
    'retries only when Effective, Upstream, and Well-known provenance all agree',
    () async {
      await publishNotes(
        donor.repository,
        donor.managedSkillId,
        'customized\n',
      );
      final source = WellKnownSourceDescriptor(
        locator: 'https://example.invalid/.well-known/skills/index.json',
        skillPath: 'drift-skill',
      );
      final request = await fromDonor(source);
      final id = await install(request);
      final before = receiver.snapshot;
      final history = await operationHistory();
      expect(before.findSkill(id)!.source, source);

      expect(
        await install(
          RemoteSkillInstall(
            packPath: request.packPath,
            effective: request.effective,
            upstream: request.upstream,
            source: WellKnownSourceDescriptor(
              locator: source.locator,
              skillPath: source.skillPath,
            ),
          ),
        ),
        id,
      );
      final mismatches = <String, RemoteSkillInstall>{
        'Effective': RemoteSkillInstall(
          packPath: request.packPath,
          effective: request.upstream!,
          upstream: request.upstream,
          source: source,
        ),
        'Upstream': RemoteSkillInstall(
          packPath: request.packPath,
          effective: request.effective,
          upstream: request.effective,
          source: source,
        ),
        'Source': RemoteSkillInstall(
          packPath: request.packPath,
          effective: request.effective,
          upstream: request.upstream,
          source: WellKnownSourceDescriptor(
            locator: source.locator,
            skillPath: 'other-path',
          ),
        ),
      };
      for (final mismatch in mismatches.entries) {
        final result = await driftSuccess(
          receiver.applyRemoteState(mismatch.value),
        );
        expect(
          result,
          isA<RemoteApplySkillSlotOccupied>().having(
            (value) => value.occupant,
            'occupant',
            id,
          ),
          reason: mismatch.key,
        );
      }
      expect(receiver.snapshot, before);
      expect(await operationHistory(), history);
      expect((await feed(before.revision)).entries, isEmpty);
      expect(await copiedNotes().readAsString(), 'customized\n');
    },
  );

  test(
    'installs a Local Source as a Synced Origin that cannot Update',
    () async {
      expect(
        donor.repository.snapshot.managedSkills.single.source,
        isA<LocalSourceDescriptor>(),
      );
      final source = SyncedOriginSourceDescriptor(
        originSourceType: SyncedOriginSourceType.local,
        originDeviceLabel: 'Donor laptop',
        displayLabel: 'Personal skills',
      );
      final request = await fromDonor(source);
      final id = await install(request);
      expect(receiver.snapshot.findSkill(id)!.source, source);
      expect((await selection(id)).upstream, request.upstream);
      await driftFailure(
        receiver.update(UpdateRequest(managedSkillIds: {id})),
        SkillsErrorCode.updateUnsupported,
      );
    },
  );

  test('reports an independent local occupant without changing it', () async {
    await donor.changeNotes(donor.sourcePath, 'local occupant\n');
    final occupant =
        await driftSuccess(
              receiver.install(
                InstallRequest(
                  source: LocalSourceDescriptor(locator: donor.sourcePath),
                  activationSelection: const ActivationSelection.none(),
                  activationMode: RequestedActivationMode.copy,
                ),
              ),
            )
            as InstallCompleted;
    final id = occupant.report.affectedSkillIds.single;
    final before = receiver.snapshot;
    final history = await operationHistory();
    final request = await fromDonor(
      SyncedOriginSourceDescriptor(
        originSourceType: SyncedOriginSourceType.local,
        originDeviceLabel: 'Donor laptop',
        displayLabel: 'Personal skills',
      ),
    );

    final result = await driftSuccess(receiver.applyRemoteState(request));

    expect(
      result,
      isA<RemoteApplySkillSlotOccupied>().having(
        (value) => value.occupant,
        'occupant',
        id,
      ),
    );
    expect(receiver.snapshot, before);
    expect(await operationHistory(), history);
    expect((await feed(before.revision)).entries, isEmpty);
    expect(await copiedNotes().readAsString(), 'local occupant\n');
  });

  test(
    'installs an Adopted Snapshot and keeps the hidden baseline through content apply and Restore Publish',
    () async {
      const slot = 'adopted-skill';
      final external = await Directory(
        path.join(donor.activationRoot(), slot),
      ).create(recursive: true);
      await donor.writeSkillMarkdown(external.path, name: slot);
      await File(
        path.join(external.path, 'notes.md'),
      ).writeAsString('original snapshot\n');
      final discovery = await driftSuccess(
        donor.repository.discoverExternalSkills(
          const DiscoverExternalSkillsRequest(scanAllKnownLocations: true),
        ),
      );
      final candidate = discovery.candidates.singleWhere(
        (value) => value.slotKey == slot,
      );
      final adopted = await driftSuccess(
        donor.repository.adopt(
          AdoptRequest(
            selection: ExternalAdoptionSelection.fromCandidate(
              candidate,
              candidate.locations.single,
            ),
          ),
        ),
      );
      final donorId = adopted.affectedSkillIds.single;
      final original = await export(
        donor.repository,
        donorId,
        'original-adoption',
      );
      await publishNotes(
        donor.repository,
        donorId,
        'published after adoption\n',
      );
      final published = await export(
        donor.repository,
        donorId,
        'published-adoption',
      );
      expect(published.effective, isNot(original.effective));
      expect(published.upstream, isNull);
      final source = SyncedOriginSourceDescriptor(
        originSourceType: SyncedOriginSourceType.adoptedSnapshot,
        originDeviceLabel: 'Donor laptop',
        displayLabel: 'Adopted skill',
      );
      final request = RemoteSkillInstall(
        packPath: packPath('published-adoption'),
        effective: published.effective,
        upstream: published.upstream,
        source: source,
      );

      final id = await install(request);
      expect(receiver.snapshot.findSkill(id)!.source, source);
      final installedAt = receiver.snapshot.revision;
      final history = await operationHistory();
      expect(await install(request), id);
      expect(receiver.snapshot.revision, installedAt);
      expect(await operationHistory(), history);
      final installed = await selection(id);
      expect(installed.effective, published.effective);
      expect(installed.upstream, isNull);
      expect(
        (await export(receiver, id, 're-exported-adoption')).upstream,
        isNull,
      );
      expect(
        await copiedNotes(slot).readAsString(),
        'published after adoption\n',
      );

      final baseline = _internalUpstream(receivingRoot, id);
      expect(baseline, published.effective);
      final installedRevision = (await driftSuccess(
        receiver.inspectPublishedHistory(
          PublishedHistoryRequest(managedSkillId: id),
        ),
      )).revisions.single.reference;
      await publishNotes(donor.repository, donorId, 'published again\n');
      final next = await export(donor.repository, donorId, 'next-adoption');
      expect(next.upstream, isNull);

      expect(
        await driftSuccess(
          receiver.applyRemoteState(
            RemoteSkillContent(
              managedSkillId: id,
              expectedEffective: installed.effective,
              effective: next.effective,
              upstream: next.upstream,
              packPath: packPath('next-adoption'),
            ),
          ),
        ),
        isA<RemoteApplyFastForwarded>(),
      );
      final applied = await selection(id);
      expect(applied.effective, next.effective);
      expect(applied.upstream, isNull);
      expect(_internalUpstream(receivingRoot, id), baseline);
      expect(await copiedNotes(slot).readAsString(), 'published again\n');

      final restored = await driftSuccess(
        receiver.restorePublish(
          RestorePublishRequest(
            managedSkillId: id,
            selectedRevision: installedRevision,
          ),
        ),
      );
      expect(restored.affectedSkillIds, {id});
      expect(
        await copiedNotes(slot).readAsString(),
        'published after adoption\n',
      );
      expect((await selection(id)).upstream, isNull);
      expect(_internalUpstream(receivingRoot, id), baseline);
    },
  );
}

Future<String> _git(List<String> args) async {
  final result = await Process.run('git', args);
  expect(result.exitCode, 0, reason: 'Git ${args.first} failed');
  return result.stdout as String;
}

RevisionId _internalUpstream(String root, ManagedSkillId id) {
  final database = sqlite3.open(
    path.join(root, 'workspace', 'workspace.sqlite'),
    mode: OpenMode.readOnly,
  );
  try {
    final row = database.select(
      'SELECT upstream_object_id FROM current_revision_selection WHERE managed_skill_id = ?',
      [id.value],
    ).single;
    return RevisionId(row['upstream_object_id'] as String);
  } finally {
    database.close();
  }
}
