import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:skills_workspace/skills_workspace.dart';
import 'package:skills_workspace/src/infrastructure/workspace_layout.dart';
import 'package:skills_workspace/src/native/revision_engine/revision_native_engine.dart';
import 'package:skills_workspace/src/native/revision_engine/revision_recovery_bundle.dart';
import 'package:test/test.dart';

import '../support/drift_facade_fixture.dart';
import '../support/remote_revision_pack_fixture.dart';

void main() {
  late DriftFacadeFixture fixture;
  late RemoteRevisionPackFixture donor;
  late SkillsRepository repository;
  late ManagedSkillId id;
  late WorkspaceLayout layout;
  late ({RevisionId revision, String packPath}) incoming;
  var losses = 0;

  setUp(() async {
    fixture = await DriftFacadeFixture.create(activate: false);
    repository = fixture.repository;
    id = fixture.managedSkillId;
    layout = WorkspaceLayout(fixture.workspacePath);
    donor = await RemoteRevisionPackFixture.create(fixture);
    final intermediate = await donor.incoming(files: {'remote.md': 'first'});
    incoming = await donor.incoming(
      parent: intermediate.revision,
      files: {'remote.md': 'second'},
    );
    losses = 0;
  });

  Future<void> reopenAfterLoss() async {
    if (repository.isOpen) await driftSuccess(repository.close());
    final store = Directory(layout.revisionStorePath(id));
    await store.rename(
      path.join(fixture.temporaryRoot.path, 'lost-${++losses}'),
    );
    repository = fixture.createRepository();
    final snapshot = await driftSuccess(repository.open());
    expect(
      snapshot.integrity.skills
          .singleWhere((s) => s.managedSkillId == id)
          .status,
      SkillIntegrityStatus.recovered,
    );
  }

  SkillsOperation<RevisionPackExport> export() => repository.exportRevisionPack(
    ExportRevisionPackRequest(
      managedSkillId: id,
      destinationPath: path.join(
        fixture.exportDirectory,
        'export-$losses.pack',
      ),
    ),
  );

  Future<void> publish() async {
    final draft = await driftSuccess(
      repository.ensureDraft(EnsureDraftRequest(managedSkillId: id)),
    );
    await fixture.changeNotes(draft.path, 'local edit\n');
    await driftSuccess(
      repository.publishDraft(PublishDraftRequest(managedSkillId: id)),
    );
  }

  Future<RemoteApplyResult> apply(RevisionId expected) => driftSuccess(
    repository.applyRemoteState(
      RemoteSkillContent(
        managedSkillId: id,
        expectedEffective: expected,
        effective: incoming.revision,
        upstream: donor.base.upstream,
        packPath: incoming.packPath,
      ),
    ),
  );

  Future<List<Object>> history() async {
    final page = await driftSuccess(
      repository.inspectPublishedHistory(
        PublishedHistoryRequest(managedSkillId: id),
      ),
    );
    return [
      for (final r in page.revisions)
        (r.reference, r.kind, r.publishedAt, r.contentHash),
    ];
  }

  test(
    'remote-only ancestry survives fast-forward and repeated Store loss',
    () async {
      expect(
        await apply(donor.base.effective),
        isA<RemoteApplyFastForwarded>(),
      );
      final before = await history();
      await reopenAfterLoss();
      expect(await history(), before);
      expect((await driftSuccess(export())).effective, incoming.revision);
      await publish();
      final secondHistory = await history();
      await reopenAfterLoss();
      expect(await history(), secondHistory);
      await driftSuccess(export());
    },
  );

  test('recovered merge can export both sides of its history', () async {
    await publish();
    final local = await driftSuccess(export());
    final merged = await apply(local.effective) as RemoteApplyMerged;
    await reopenAfterLoss();
    expect((await driftSuccess(export())).effective, merged.newEffective);
  });

  test('local publish preserves the installed donor history', () async {
    final install = await donor.incoming(
      parent: incoming.revision,
      files: {
        'SKILL.md':
            '---\nname: remote-install\ndescription: Remote install\n---\n# Skill\n',
      },
    );
    final result = await driftSuccess(
      repository.applyRemoteState(
        RemoteSkillInstall(
          packPath: install.packPath,
          effective: install.revision,
          upstream: donor.base.upstream,
          source: SyncedOriginSourceDescriptor(
            originSourceType: SyncedOriginSourceType.local,
            originDeviceLabel: 'Donor',
            displayLabel: 'Remote Skill',
          ),
        ),
      ),
    );
    id = (result as RemoteApplyInstalled).managedSkillId;
    await publish();
    final before = await driftSuccess(export());
    await reopenAfterLoss();
    expect((await driftSuccess(export())).effective, before.effective);
  });

  test(
    'Store recovered from a legacy short bundle can still publish and recover',
    () async {
      expect(
        await apply(donor.base.effective),
        isA<RemoteApplyFastForwarded>(),
      );
      await driftSuccess(repository.close());
      final bundle = Directory(layout.revisionBundlePath(id));
      await fixture.makeWritable(bundle.path);
      final manifestFile = File(path.join(bundle.path, 'manifest.json'));
      const codec = RevisionRecoveryBundleCodec();
      final manifest = codec.decodeManifest(await manifestFile.readAsBytes());
      final engine = RevisionNativeEngine.open();
      try {
        final short = await fixture.temporaryRoot.createTemp('legacy');
        engine.createRecoveryPack(
          repositoryPath: layout.revisionStorePath(id),
          bundleStagingPath: short.path,
          retainedRoots: manifest.retainedPublishedRoots,
        );
        for (final name in ['objects.pack', 'objects.idx']) {
          await File(
            path.join(short.path, name),
          ).copy(path.join(bundle.path, name));
        }
        final bytes = codec.encodeManifest(
          codec.createManifest(
            sourceLineageId: manifest.sourceLineageId,
            currentUpstream: manifest.currentUpstream,
            currentEffective: manifest.currentEffective,
            retainedPublishedRoots: manifest.retainedPublishedRoots,
            packBytes: await File(
              path.join(bundle.path, 'objects.pack'),
            ).readAsBytes(),
            indexBytes: await File(
              path.join(bundle.path, 'objects.idx'),
            ).readAsBytes(),
          ),
        );
        await manifestFile.writeAsBytes(bytes);
        await File(
          path.join(bundle.path, 'COMPLETE'),
        ).writeAsBytes(codec.createCompletionFence(bytes));
      } finally {
        engine.close();
      }
      await reopenAfterLoss();
      await driftFailure(export(), SkillsErrorCode.revisionStoreCorrupt);
      await publish();
      await reopenAfterLoss();
      await driftFailure(export(), SkillsErrorCode.revisionStoreCorrupt);
    },
  );
}
