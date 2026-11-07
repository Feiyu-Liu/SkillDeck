import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:skills_workspace/skills_workspace.dart';
import 'package:skills_workspace/src/infrastructure/workspace_layout.dart';
import 'package:skills_workspace/src/native/revision_engine/revision_recovery_bundle.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

void main() {
  test(
    'startup restores a corrupt live Store from the real Revision Bundle',
    () async {
      final fixture = await _RecoveryFixture.create();
      addTearDown(fixture.dispose);

      var repository = fixture.createRepository();
      await _expectSuccess(repository.open(), label: 'initial open');
      final installed =
          (await _expectSuccess(
                    repository.install(
                      InstallRequest(
                        source: fixture.source,
                        activationSelection: const ActivationSelection.none(),
                      ),
                    ),
                    label: 'install',
                  )
                  as InstallCompleted)
              .report;
      final managedSkillId = installed.affectedSkillIds.single;

      final draft = await _expectSuccess(
        repository.ensureDraft(
          EnsureDraftRequest(managedSkillId: managedSkillId),
        ),
        label: 'ensure Draft',
      );
      await File(
        path.join(draft.path, 'notes.md'),
      ).writeAsString(_publishedNotes, flush: true);
      await File(
        path.join(draft.path, 'local.md'),
      ).writeAsString(_localOnlyContent, flush: true);
      await _expectSuccess(
        repository.publishDraft(
          PublishDraftRequest(managedSkillId: managedSkillId),
        ),
        label: 'publish Draft',
      );

      final pointersBefore = _readRevisionPointers(
        fixture.workspaceRoot,
        managedSkillId,
      );
      final skillBefore = repository.snapshot.findSkill(managedSkillId)!;
      final historyBefore = await _expectSuccess(
        repository.inspectPublishedHistory(
          PublishedHistoryRequest(managedSkillId: managedSkillId),
        ),
        label: 'history before recovery',
      );
      final installRevision = historyBefore.revisions.singleWhere(
        (revision) => revision.kind == WorkspaceOperationKind.install,
      );
      final publishedRevision = historyBefore.revisions.singleWhere(
        (revision) => revision.kind == WorkspaceOperationKind.publishDraft,
      );
      final fullContentBefore = await _expectSuccess(
        repository.inspectDiff(
          InspectDiffRequest(
            managedSkillId: managedSkillId,
            to: publishedRevision.reference,
          ),
        ),
        label: 'full content before recovery',
      );
      final publishedDiffBefore = await _expectSuccess(
        repository.inspectDiff(
          InspectDiffRequest(
            managedSkillId: managedSkillId,
            from: installRevision.reference,
            to: publishedRevision.reference,
          ),
        ),
        label: 'published diff before recovery',
      );
      expect(
        fullContentBefore.files.map((file) => file.path),
        containsAll(<String>['SKILL.md', 'local.md', 'notes.md']),
      );
      expect(
        _diffText(fullContentBefore),
        allOf(
          contains(_publishedNotes.trim()),
          contains(_localOnlyContent.trim()),
        ),
      );
      await _expectEffectiveText(
        repository: repository,
        managedSkillId: managedSkillId,
        relativePath: 'notes.md',
        expected: _publishedNotes,
      );

      final layout = WorkspaceLayout(fixture.workspaceRoot.absolute.path);
      final storePath = layout.revisionStorePath(managedSkillId);
      final bundlePath = layout.revisionBundlePath(managedSkillId);
      final bundleBytesBefore = await _verifyRealBundle(
        bundlePath: bundlePath,
        pointers: pointersBefore,
      );
      expect(await Directory(storePath).exists(), isTrue);

      final historyEvidenceBefore = _historyEvidence(historyBefore);
      final fullContentEvidenceBefore = _diffEvidence(fullContentBefore);
      final publishedDiffEvidenceBefore = _diffEvidence(publishedDiffBefore);
      await _expectSuccess(
        repository.close(),
        label: 'close before corruption',
      );

      await _replaceStoreWithCorruption(storePath);
      final corruptionMarker = File(path.join(storePath, 'CORRUPT'));
      expect(await corruptionMarker.exists(), isTrue);
      final corruptedEntries = await Directory(
        storePath,
      ).list().map((entry) => path.basename(entry.path)).toList();
      expect(corruptedEntries, <String>['CORRUPT']);

      repository = fixture.createRepository();
      final reopened = await _expectSuccess(
        repository.open(),
        label: 'reopen and recover',
      );
      expect(
        reopened.findSkill(managedSkillId),
        isNotNull,
        reason: 'the committed Skill must remain selected during recovery',
      );
      expect(
        _readRevisionPointers(fixture.workspaceRoot, managedSkillId),
        pointersBefore,
        reason: 'startup must validate the same active Store',
      );
      expect(reopened.integrity.skills, hasLength(1));
      expect(reopened.integrity.skills.single.managedSkillId, managedSkillId);
      expect(
        reopened.integrity.skills.single.status,
        SkillIntegrityStatus.recovered,
      );
      expect(
        await corruptionMarker.exists(),
        isFalse,
        reason: 'the corrupt Store must be replaced before integrity reports',
      );
      expect(reopened.integrity.status, WorkspaceIntegrityStatus.recovered);
      final pointersAfter = _readRevisionPointers(
        fixture.workspaceRoot,
        managedSkillId,
      );
      expect(pointersAfter, pointersBefore);
      expect(
        reopened.findSkill(managedSkillId)?.currentRevision,
        skillBefore.currentRevision,
      );

      final historyAfter = await _expectSuccess(
        repository.inspectPublishedHistory(
          PublishedHistoryRequest(managedSkillId: managedSkillId),
        ),
        label: 'history after recovery',
      );
      expect(_historyEvidence(historyAfter), historyEvidenceBefore);

      final fullContentAfter = await _expectSuccess(
        repository.inspectDiff(
          InspectDiffRequest(
            managedSkillId: managedSkillId,
            to: publishedRevision.reference,
          ),
        ),
        label: 'full content after recovery',
      );
      final publishedDiffAfter = await _expectSuccess(
        repository.inspectDiff(
          InspectDiffRequest(
            managedSkillId: managedSkillId,
            from: installRevision.reference,
            to: publishedRevision.reference,
          ),
        ),
        label: 'published diff after recovery',
      );
      expect(
        _diffEvidence(fullContentAfter),
        equals(fullContentEvidenceBefore),
      );
      expect(
        _diffEvidence(publishedDiffAfter),
        equals(publishedDiffEvidenceBefore),
      );
      final bundleBytesAfter = await _readBundleBytes(bundlePath);
      expect(bundleBytesAfter.manifest, bundleBytesBefore.manifest);
      expect(bundleBytesAfter.pack, bundleBytesBefore.pack);
      expect(bundleBytesAfter.index, bundleBytesBefore.index);
      expect(
        bundleBytesAfter.complete,
        bundleBytesBefore.complete,
        reason: 'startup recovery must consume, not rewrite, the live Bundle',
      );
      await _expectEffectiveText(
        repository: repository,
        managedSkillId: managedSkillId,
        relativePath: 'local.md',
        expected: _localOnlyContent,
      );

      await _expectSuccess(repository.close(), label: 'final close');
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

const _skillName = 'recovery-bundle-e2e';
const _description = 'Revision Recovery Bundle startup E2E';
const _baseNotes = 'base notes\n';
const _publishedNotes = 'locally published notes\n';
const _localOnlyContent = 'retained only by the published revision\n';

typedef _RevisionPointers = ({
  String sourceLineage,
  String upstream,
  String effective,
});

typedef _BundleBytes = ({
  List<int> manifest,
  List<int> pack,
  List<int> index,
  List<int> complete,
});

typedef _HistoryEvidence = ({
  OperationSubjectReference reference,
  WorkspaceOperationKind kind,
  int publishedAtMicros,
  String contentHash,
});

final class _RecoveryFixture {
  _RecoveryFixture._({
    required this.temporaryRoot,
    required this.workspaceRoot,
    required this.agentHome,
    required this.sourceRoot,
  });

  final Directory temporaryRoot;
  final Directory workspaceRoot;
  final Directory agentHome;
  final Directory sourceRoot;
  final List<SkillsRepository> _repositories = <SkillsRepository>[];

  static Future<_RecoveryFixture> create() async {
    final temporaryRoot = await Directory.systemTemp.createTemp(
      'revision-bundle-startup-e2e-',
    );
    final workspaceRoot = Directory(path.join(temporaryRoot.path, 'workspace'));
    final agentHome = Directory(path.join(temporaryRoot.path, 'agent-home'));
    final sourceRoot = Directory(path.join(temporaryRoot.path, 'source'));
    await agentHome.create(recursive: true);
    await sourceRoot.create(recursive: true);
    await File(path.join(sourceRoot.path, 'SKILL.md')).writeAsString(
      '---\n'
      'name: $_skillName\n'
      'description: $_description\n'
      '---\n'
      '# Recovery Bundle E2E\n',
      flush: true,
    );
    await File(
      path.join(sourceRoot.path, 'notes.md'),
    ).writeAsString(_baseNotes, flush: true);
    return _RecoveryFixture._(
      temporaryRoot: temporaryRoot,
      workspaceRoot: workspaceRoot,
      agentHome: agentHome,
      sourceRoot: sourceRoot,
    );
  }

  LocalSourceDescriptor get source =>
      LocalSourceDescriptor(locator: sourceRoot.absolute.path);

  SkillsRepository createRepository() {
    final repository = createSkillsRepository(
      SkillsRepositoryConfiguration(
        rootPath: workspaceRoot.absolute.path,
        agentHomePath: agentHome.absolute.path,
        defaultLockWaitPolicy: LockWaitPolicy.wait(
          timeout: const Duration(seconds: 10),
        ),
      ),
    );
    _repositories.add(repository);
    return repository;
  }

  Future<void> dispose() async {
    for (final repository in _repositories.reversed) {
      if (!repository.isOpen) continue;
      try {
        await repository.close().completed;
      } on Object {
        // Preserve the original failure while still releasing later resources.
      }
    }
    if (!await temporaryRoot.exists()) return;
    await _makeTreeWritable(temporaryRoot.path);
    await temporaryRoot.delete(recursive: true);
  }
}

Future<T> _expectSuccess<T>(
  SkillsOperation<T> operation, {
  required String label,
}) async {
  final result = await operation.completed;
  expect(result, isA<SkillsSuccess<T>>(), reason: '$label: $result');
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
  final content = await _expectSuccess(
    repository.readEffectiveFile(
      ReadEffectiveFileRequest(
        managedSkillId: managedSkillId,
        expectedContentHash: manifest.contentHash,
        relativePath: relativePath,
      ),
    ),
    label: 'read recovered effective file',
  );
  expect(utf8.decode(content.bytes, allowMalformed: false), expected);
}

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
      'SELECT crs.source_lineage_id, '
      'crs.upstream_object_id, crs.effective_object_id '
      'FROM current_revision_selection crs '
      'INNER JOIN source_lineages sl ON sl.id = crs.source_lineage_id '
      'AND sl.managed_skill_id = crs.managed_skill_id '
      'WHERE crs.managed_skill_id = ?',
      <Object?>[managedSkillId.value],
    );
    if (rows.length != 1) {
      throw StateError('Expected exactly one current Revision selection.');
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

Future<_BundleBytes> _verifyRealBundle({
  required String bundlePath,
  required _RevisionPointers pointers,
}) async {
  final bytes = await _readBundleBytes(bundlePath);
  expect(bytes.manifest, isNotEmpty);
  expect(bytes.pack, isNotEmpty);
  expect(bytes.index, isNotEmpty);
  expect(bytes.complete, isNotEmpty);

  final manifest = const RevisionRecoveryBundleCodec().verify(
    manifestBytes: bytes.manifest,
    completionFenceBytes: bytes.complete,
    packBytes: bytes.pack,
    indexBytes: bytes.index,
  );
  expect(manifest.sourceLineageId, pointers.sourceLineage);
  expect(manifest.currentUpstream.value, pointers.upstream);
  expect(manifest.currentEffective.value, pointers.effective);
  expect(
    manifest.retainedPublishedRoots.map((root) => root.value),
    containsAll(<String>[pointers.upstream, pointers.effective]),
  );
  return bytes;
}

Future<_BundleBytes> _readBundleBytes(String bundlePath) async => (
  manifest: await File(path.join(bundlePath, 'manifest.json')).readAsBytes(),
  pack: await File(path.join(bundlePath, 'objects.pack')).readAsBytes(),
  index: await File(path.join(bundlePath, 'objects.idx')).readAsBytes(),
  complete: await File(path.join(bundlePath, 'COMPLETE')).readAsBytes(),
);

Future<void> _replaceStoreWithCorruption(String storePath) async {
  final store = Directory(storePath);
  if (await store.exists()) {
    await _makeTreeWritable(store.path);
    await store.delete(recursive: true);
  }
  await store.create(recursive: true);
  await File(
    path.join(store.path, 'CORRUPT'),
  ).writeAsString('not a bare Git repository', flush: true);
}

Future<void> _makeTreeWritable(String rootPath) async {
  if (!await FileSystemEntity.isDirectory(rootPath)) return;
  final ProcessResult result;
  if (Platform.isWindows) {
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
    throw FileSystemException('Failed to make the test tree writable.');
  }
}

List<_HistoryEvidence> _historyEvidence(PublishedHistoryPage history) => [
  for (final revision in history.revisions)
    (
      reference: revision.reference,
      kind: revision.kind,
      publishedAtMicros: revision.publishedAt.microsecondsSinceEpoch,
      contentHash: revision.contentHash,
    ),
];

List<Map<String, Object?>> _diffEvidence(SkillDiff diff) => [
  for (final file in diff.files)
    <String, Object?>{
      'path': file.path,
      'previousPath': file.previousPath,
      'status': file.status.name,
      'isBinary': file.isBinary,
      'additions': file.additions,
      'deletions': file.deletions,
      'hunks': <Map<String, Object?>>[
        for (final hunk in file.hunks)
          <String, Object?>{
            'header': hunk.header,
            'lines': <Map<String, Object?>>[
              for (final line in hunk.lines)
                <String, Object?>{
                  'kind': line.kind.name,
                  'text': line.text,
                  'oldLineNumber': line.oldLineNumber,
                  'newLineNumber': line.newLineNumber,
                },
            ],
          },
      ],
    },
];

String _diffText(SkillDiff diff) => [
  for (final file in diff.files)
    for (final hunk in file.hunks)
      for (final line in hunk.lines) line.text,
].join('\n');
