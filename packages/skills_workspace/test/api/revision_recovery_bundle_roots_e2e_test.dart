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
  test(
    'bundle manifest covers retained revisions across local and remote writes',
    () async {
      final fixture = await DriftFacadeFixture.create(activate: false);
      final repository = fixture.repository;
      final id = fixture.managedSkillId;
      final layout = WorkspaceLayout(fixture.workspacePath);
      final initial = (await fixture.history()).revisions.single;
      await _expectRetainedRoots(layout, id, 'Install');

      final draft = await driftSuccess(
        repository.ensureDraft(EnsureDraftRequest(managedSkillId: id)),
      );
      await fixture.changeNotes(draft.path, 'Published locally\n');
      await driftSuccess(
        repository.publishDraft(PublishDraftRequest(managedSkillId: id)),
      );
      await _expectRetainedRoots(layout, id, 'Publish Draft');

      await driftSuccess(
        repository.restorePublish(
          RestorePublishRequest(
            managedSkillId: id,
            selectedRevision: initial.reference,
          ),
        ),
      );
      final afterRestore = await _expectRetainedRoots(
        layout,
        id,
        'Restore Publish',
      );
      expect(
        afterRestore,
        hasLength(3),
        reason: 'includes the superseded publication',
      );

      final donor = await RemoteRevisionPackFixture.create(fixture);
      final remote = await donor.incoming(
        files: {'notes.md': 'Published remotely\n'},
      );
      expect(
        await driftSuccess(
          repository.applyRemoteState(
            RemoteSkillContent(
              managedSkillId: id,
              expectedEffective: donor.base.effective,
              effective: remote.revision,
              upstream: donor.base.upstream,
              packPath: remote.packPath,
            ),
          ),
        ),
        isA<RemoteApplyFastForwarded>(),
      );
      final afterRemote = await _expectRetainedRoots(
        layout,
        id,
        'Remote content apply',
      );
      expect(afterRemote, {...afterRestore, remote.revision.value});

      const newName = 'remote-install';
      final newSkill = await donor.incoming(
        files: {
          'SKILL.md':
              '---\nname: $newName\ndescription: Remote Skill\n---\n# Skill\n',
        },
      );
      final remoteInstall = await driftSuccess(
        repository.applyRemoteState(
          RemoteSkillInstall(
            packPath: newSkill.packPath,
            effective: newSkill.revision,
            upstream: donor.base.upstream,
            source: SyncedOriginSourceDescriptor(
              originSourceType: SyncedOriginSourceType.local,
              originDeviceLabel: 'Donor',
              displayLabel: 'Remote Skill',
            ),
          ),
        ),
      );
      expect(remoteInstall, isA<RemoteApplyInstalled>());
      final newId = (remoteInstall as RemoteApplyInstalled).managedSkillId;
      expect(repository.snapshot.findSkill(newId)!.slotKey, newName);
      final installedRoots = await _expectRetainedRoots(
        layout,
        newId,
        'Remote install',
      );
      expect(installedRoots, {
        newSkill.revision.value,
        donor.base.upstream!.value,
      });
      expect(
        await _expectRetainedRoots(layout, id, 'Original Skill'),
        afterRemote,
      );
    },
  );
}

Future<Set<String>> _expectRetainedRoots(
  WorkspaceLayout layout,
  ManagedSkillId id,
  String step,
) async {
  final refs = await Process.run('git', [
    '--git-dir=${layout.revisionStorePath(id)}',
    'for-each-ref',
    '--format=%(objectname)',
    'refs/skills-workspace/r/',
  ]);
  expect(refs.exitCode, 0, reason: step);
  final desired = (refs.stdout as String).trim().split(RegExp(r'\s+')).toSet();
  expect(desired, isNot(contains('')), reason: step);
  final manifest = const RevisionRecoveryBundleCodec().decodeManifest(
    await File(
      path.join(layout.revisionBundlePath(id), 'manifest.json'),
    ).readAsBytes(),
  );
  expect(
    manifest.retainedPublishedRoots.map((root) => root.value),
    containsAll(desired),
    reason: step,
  );
  final scratch = await Directory.systemTemp.createTemp('bundle-history-');
  final restored = path.join(scratch.path, 'restored.git');
  final engine = RevisionNativeEngine.open();
  try {
    final bundle = layout.revisionBundlePath(id);
    engine.restoreRecoveryPack(
      stagedRepositoryPath: restored,
      packPath: path.join(bundle, 'objects.pack'),
      indexPath: path.join(bundle, 'objects.idx'),
      retainedRoots: manifest.retainedPublishedRoots,
    );
    Future<Set<String>> commits(String store) async {
      final result = await Process.run('git', [
        '--git-dir=$store',
        'rev-list',
        ...manifest.retainedPublishedRoots.map((root) => root.value),
      ]);
      expect(result.exitCode, 0, reason: step);
      return (result.stdout as String).trim().split(RegExp(r'\s+')).toSet();
    }

    expect(
      await commits(restored),
      await commits(layout.revisionStorePath(id)),
      reason: step,
    );
  } finally {
    engine.close();
    await scratch.delete(recursive: true);
  }
  return desired;
}
