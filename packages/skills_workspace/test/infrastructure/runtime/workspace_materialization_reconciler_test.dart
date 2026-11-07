import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:skills_workspace/src/application/runtime/revision_engine_port.dart';
import 'package:skills_workspace/src/application/revision_store/managed_skill_revision_access_gate.dart';
import 'package:skills_workspace/src/application/runtime/normalized_skill_tree_hash.dart';
import 'package:skills_workspace/src/domain/identifiers.dart';
import 'package:skills_workspace/src/domain/cancellation.dart';
import 'package:skills_workspace/src/domain/revision_content.dart';
import 'package:skills_workspace/src/domain/public_models.dart';
import 'package:skills_workspace/src/application/ports/published_artifact_ports.dart';
import 'package:skills_workspace/src/application/ports/workspace_lifecycle_ports.dart';
import 'package:skills_workspace/src/infrastructure/database/workspace_database.dart';
import 'package:skills_workspace/src/composition/workspace_materialization_reconciler.dart';
import 'package:skills_workspace/src/infrastructure/content/direct_revision_content_worker.dart';
import 'package:skills_workspace/src/infrastructure/content/file_system_published_artifact_inspector.dart';
import 'package:skills_workspace/src/infrastructure/workspace_layout.dart';
import 'package:skills_workspace/src/platform/filesystem/durable_workspace_filesystem.dart';
import 'package:skills_workspace/src/platform/filesystem/file_system_published_artifact_metadata_observer.dart';
import 'package:test/test.dart';

const _skill = '123e4567-e89b-42d3-a456-426614174000';
const _lineage = '123e4567-e89b-42d3-a456-426614174001';
const _activation = '123e4567-e89b-42d3-a456-426614174002';
const _object = '1111111111111111111111111111111111111111';
final _executableIntent = !Platform.isWindows;
final _hash = computeNormalizedSkillTreeHash(<NormalizedSkillFile>[
  NormalizedSkillFile(
    relativePath: 'SKILL.md',
    bytes: 'managed'.codeUnits,
    isExecutable: false,
  ),
  NormalizedSkillFile(
    relativePath: 'scripts/run.sh',
    bytes: '#!/bin/sh\n'.codeUnits,
    isExecutable: _executableIntent,
  ),
]);

void main() {
  late Directory temporary;
  late WorkspaceLayout layout;
  late WorkspaceDatabase database;
  late Directory activationRoot;
  late _TreeRevisionEngine revisionEngine;
  late DriftWorkspaceMaterializationReconciler reconciler;
  late PlatformDurableWorkspaceFilesystem filesystem;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp(
      'skills-workspace-materialization-reconcile-',
    );
    layout = WorkspaceLayout(path.join(temporary.path, 'workspace'));
    activationRoot = Directory(path.join(temporary.path, 'activation'));
    database = WorkspaceDatabase.forFile(File(layout.databasePath));
    await database.select(database.workspaceMetadata).getSingle();
    revisionEngine = _TreeRevisionEngine(
      NormalizedSkillTree(
        files: <NormalizedSkillFile>[
          NormalizedSkillFile(
            relativePath: 'SKILL.md',
            bytes: 'managed'.codeUnits,
            isExecutable: false,
          ),
          NormalizedSkillFile(
            relativePath: 'scripts/run.sh',
            bytes: '#!/bin/sh\n'.codeUnits,
            isExecutable: _executableIntent,
          ),
        ],
        contentHash: _hash,
        byteSize: 17,
      ),
    );
    filesystem = PlatformDurableWorkspaceFilesystem();
    reconciler = DriftWorkspaceMaterializationReconciler(
      database: database,
      layout: layout,
      revisionEngine: revisionEngine,
      filesystem: filesystem,
      artifactInspector: const FileSystemPublishedArtifactInspector(
        contentWorker: DirectRevisionContentWorker(),
        metadataObserver: FileSystemPublishedArtifactMetadataObserver(),
      ),
      accessGate: ManagedSkillRevisionAccessGate(),
    );
  });

  tearDown(() async {
    await database.close();
    for (final targetPath in <String>[
      layout.repositoryCopiesRoot,
      activationRoot.path,
    ]) {
      if (await FileSystemEntity.type(targetPath, followLinks: false) !=
          FileSystemEntityType.notFound) {
        await filesystem.removeOwnedPath(
          targetPath: targetPath,
          ownerRoot: temporary.path,
        );
      }
    }
    await temporary.delete(recursive: true);
  });

  test(
    'inspection returns each artifact and activation provenance without repairing',
    () async {
      await _insertSelection(database, activationRoot.path, mode: 'copy');
      final repositoryCopyPath = layout.repositoryCopyPath('sample');
      await Directory(repositoryCopyPath).create(recursive: true);
      await File(
        path.join(repositoryCopyPath, 'SKILL.md'),
      ).writeAsString('external');

      final inspection = await reconciler.inspectSkillMaterializations(
        ManagedSkillId(_skill),
      );

      expect(inspection.effectiveObjectId, RevisionObjectId(_object));
      expect(inspection.effectiveContentHash, _hash);
      expect(inspection.artifacts, hasLength(2));
      final repositoryArtifact = inspection.artifacts.first;
      expect(
        repositoryArtifact.locationKind,
        SkillDriftLocationKind.repositoryCopy,
      );
      expect(repositoryArtifact.targetPath, repositoryCopyPath);
      expect(repositoryArtifact.activation, isNull);
      expect(
        repositoryArtifact.inspection.mismatchKind,
        PublishedArtifactMismatchKind.contentChanged,
      );
      expect(repositoryArtifact.inspection.fingerprint, isNotNull);
      final activationArtifact = inspection.artifacts.last;
      expect(
        activationArtifact.locationKind,
        SkillDriftLocationKind.copyActivation,
      );
      expect(activationArtifact.activation!.location, activationRoot.path);
      expect(activationArtifact.activation!.agentIds, ['agent']);
      expect(
        activationArtifact.inspection.state,
        PublishedArtifactState.missing,
      );
      expect(revisionEngine.readPaths, isEmpty);
      expect(
        await File(path.join(repositoryCopyPath, 'SKILL.md')).readAsString(),
        'external',
      );
    },
  );

  test('unsafe materializations produce a typed drift failure', () async {
    await _insertSelection(database, activationRoot.path, mode: 'copy');
    await Directory(
      path.join(layout.repositoryCopyPath('sample'), '.git'),
    ).create(recursive: true);
    await File(
      path.join(layout.repositoryCopyPath('sample'), 'SKILL.md'),
    ).writeAsString('external');

    await expectLater(
      reconciler.inspectSkillMaterializations(ManagedSkillId(_skill)),
      throwsA(isA<SkillDriftUnsafe>()),
    );
    expect(revisionEngine.readPaths, isEmpty);
  });

  test(
    'oversized wrong-type files remain pending with restore-only metadata evidence',
    () async {
      await _insertSelection(database, activationRoot.path, mode: 'copy');
      await Directory(layout.repositoryCopiesRoot).create(recursive: true);
      final repositoryPath = layout.repositoryCopyPath('sample');
      final file = await File(repositoryPath).open(mode: FileMode.write);
      try {
        await file.truncate(50 * 1024 * 1024 + 1);
      } finally {
        await file.close();
      }
      final report = await reconciler.reconcileMaterializations(
        isolatedSkillIds: const {},
        repairMismatching: false,
        repairMissing: false,
      );
      expect(report.mismatchingArtifactCount, 1);
      final inspected = await reconciler.inspectSkillMaterializations(
        ManagedSkillId(_skill),
      );
      final artifact = inspected.artifacts.first.inspection;
      expect(artifact.state, PublishedArtifactState.mismatching);
      expect(
        artifact.mismatchKind,
        PublishedArtifactMismatchKind.wrongEntryType,
      );
      expect(artifact.fingerprint, isNull);
      expect(artifact.metadataFingerprint, isNotNull);
      expect(await File(repositoryPath).length(), 50 * 1024 * 1024 + 1);
    },
  );

  test(
    'wrong-type Git directories can be reviewed for link restoration',
    () async {
      await _insertSelection(
        database,
        activationRoot.path,
        mode: 'symbolicLink',
      );
      await _writeExpectedTree(filesystem, layout.repositoryCopyPath('sample'));
      final wrongDirectory = path.join(activationRoot.path, 'sample');
      await Directory(
        path.join(wrongDirectory, '.git'),
      ).create(recursive: true);
      await File(
        path.join(wrongDirectory, '.git', 'config'),
      ).writeAsString('external');
      final inspected = await reconciler.inspectSkillMaterializations(
        ManagedSkillId(_skill),
      );
      final artifact = inspected.artifacts.last.inspection;
      expect(artifact.state, PublishedArtifactState.mismatching);
      expect(
        artifact.mismatchKind,
        PublishedArtifactMismatchKind.wrongEntryType,
      );
      expect(artifact.fingerprint, isNull);
      expect(artifact.metadataFingerprint, isNotNull);
    },
  );

  test(
    'cancelled per-artifact inspection does not scan or mutate materializations',
    () async {
      await _insertSelection(database, activationRoot.path, mode: 'copy');
      final cancellation = CancellationSource();
      await cancellation.cancel();
      await expectLater(
        reconciler.inspectSkillMaterializations(
          ManagedSkillId(_skill),
          cancellationToken: cancellation.token,
        ),
        throwsA(isA<SkillDriftUnsafe>()),
      );
      expect(revisionEngine.readPaths, isEmpty);
      expect(
        await Directory(layout.repositoryCopyPath('sample')).exists(),
        isFalse,
      );
    },
  );

  test(
    'symbolic-link inspection identifies its managed mode and wrong target',
    () async {
      await _insertSelection(
        database,
        activationRoot.path,
        mode: 'symbolicLink',
      );
      await _writeExpectedTree(filesystem, layout.repositoryCopyPath('sample'));
      await activationRoot.create(recursive: true);
      await Link(path.join(activationRoot.path, 'sample')).create('wrong');

      final inspection = await reconciler.inspectSkillMaterializations(
        ManagedSkillId(_skill),
      );

      expect(
        inspection.artifacts.last.locationKind,
        SkillDriftLocationKind.symbolicLinkActivation,
      );
      expect(
        inspection.artifacts.last.activation!.mode,
        ActivationMode.symbolicLink,
      );
      expect(
        inspection.artifacts.last.inspection.mismatchKind,
        PublishedArtifactMismatchKind.wrongLinkTarget,
      );
      expect(revisionEngine.readPaths, isEmpty);
    },
    skip: Platform.isWindows ? 'Requires symbolic-link capability.' : false,
  );

  test(
    'repairs Repository Copy and copy Activation from Effective tree',
    () async {
      await _insertSelection(database, activationRoot.path, mode: 'copy');
      final repositoryCopy = Directory(layout.repositoryCopyPath('sample'));
      final activationCopy = Directory(
        path.join(activationRoot.path, 'sample'),
      );
      await repositoryCopy.create(recursive: true);
      await File(
        path.join(repositoryCopy.path, 'SKILL.md'),
      ).writeAsString('drift');
      await activationCopy.create(recursive: true);
      await File(
        path.join(activationCopy.path, 'SKILL.md'),
      ).writeAsString('drift');

      await reconciler.reconcileMaterializations(isolatedSkillIds: const {});

      expect(
        await File(path.join(repositoryCopy.path, 'SKILL.md')).readAsString(),
        'managed',
      );
      expect(
        await File(path.join(activationCopy.path, 'SKILL.md')).readAsString(),
        'managed',
      );
      expect(
        await File(
          path.join(activationCopy.path, 'scripts', 'run.sh'),
        ).readAsString(),
        '#!/bin/sh\n',
      );
      expect(revisionEngine.readPaths, hasLength(1));
    },
  );

  test('unchanged materializations are not read or republished', () async {
    await _insertSelection(database, activationRoot.path, mode: 'copy');
    final repositoryCopyPath = layout.repositoryCopyPath('sample');
    final activationCopyPath = path.join(activationRoot.path, 'sample');
    await _writeExpectedTree(filesystem, repositoryCopyPath);
    await _writeExpectedTree(filesystem, activationCopyPath);
    final preservedAt = DateTime.utc(2001);
    final repositorySkill = File(path.join(repositoryCopyPath, 'SKILL.md'));
    final activationSkill = File(path.join(activationCopyPath, 'SKILL.md'));
    await repositorySkill.setLastModified(preservedAt);
    await activationSkill.setLastModified(preservedAt);

    final report = await reconciler.reconcileMaterializations(
      isolatedSkillIds: const {},
    );

    expect(revisionEngine.readPaths, isEmpty);
    expect(report.inspectedArtifactCount, 2);
    expect(report.inspectedFileCount, 4);
    expect(report.inspectedByteCount, 34);
    expect(report.repairedArtifactCount, 0);
    expect((await repositorySkill.stat()).modified.toUtc(), preservedAt);
    expect((await activationSkill.stat()).modified.toUtc(), preservedAt);
  });

  test('one drifted Activation repairs only that Activation', () async {
    await _insertSelection(database, activationRoot.path, mode: 'copy');
    final repositoryCopyPath = layout.repositoryCopyPath('sample');
    final activationCopyPath = path.join(activationRoot.path, 'sample');
    await _writeExpectedTree(filesystem, repositoryCopyPath);
    await _writeExpectedTree(filesystem, activationCopyPath);
    final preservedAt = DateTime.utc(2001);
    final repositorySkill = File(path.join(repositoryCopyPath, 'SKILL.md'));
    await repositorySkill.setLastModified(preservedAt);
    await File(
      path.join(activationCopyPath, 'SKILL.md'),
    ).writeAsString('drift');

    final report = await reconciler.reconcileMaterializations(
      isolatedSkillIds: const {},
    );

    expect(revisionEngine.readPaths, hasLength(1));
    expect(report.repairedArtifactCount, 1);
    expect((await repositorySkill.stat()).modified.toUtc(), preservedAt);
    expect(
      await File(path.join(activationCopyPath, 'SKILL.md')).readAsString(),
      'managed',
    );
  });

  test(
    'content drift is reported without replacement when repair is disabled',
    () async {
      await _insertSelection(database, activationRoot.path, mode: 'copy');
      final repositoryCopyPath = layout.repositoryCopyPath('sample');
      final activationCopyPath = path.join(activationRoot.path, 'sample');
      await _writeExpectedTree(filesystem, repositoryCopyPath);
      await _writeExpectedTree(filesystem, activationCopyPath);
      await File(
        path.join(activationCopyPath, 'SKILL.md'),
      ).writeAsString('external');

      final report = await reconciler.reconcileMaterializations(
        isolatedSkillIds: const {},
        selectedSkillIds: {ManagedSkillId(_skill)},
        repairMismatching: false,
        repairMissing: false,
      );

      expect(report.mismatchingArtifactCount, 1);
      expect(report.mismatchingSkillIds, [ManagedSkillId(_skill)]);
      expect(
        await File(path.join(activationCopyPath, 'SKILL.md')).readAsString(),
        'external',
      );
      expect(revisionEngine.readPaths, isEmpty);
    },
  );

  test(
    'a missing Repository Copy does not republish a matching Activation',
    () async {
      await _insertSelection(database, activationRoot.path, mode: 'copy');
      final repositoryCopyPath = layout.repositoryCopyPath('sample');
      final activationCopyPath = path.join(activationRoot.path, 'sample');
      await _writeExpectedTree(filesystem, activationCopyPath);
      final preservedAt = DateTime.utc(2001);
      final activationSkill = File(path.join(activationCopyPath, 'SKILL.md'));
      await activationSkill.setLastModified(preservedAt);

      final report = await reconciler.reconcileMaterializations(
        isolatedSkillIds: const {},
      );

      expect(revisionEngine.readPaths, hasLength(1));
      expect(report.repairedArtifactCount, 1);
      expect(
        await File(path.join(repositoryCopyPath, 'SKILL.md')).readAsString(),
        'managed',
      );
      expect((await activationSkill.stat()).modified.toUtc(), preservedAt);
    },
  );

  test(
    'leaves every materialization untouched for an isolated Skill',
    () async {
      await _insertSelection(database, activationRoot.path, mode: 'copy');
      final repositoryCopyPath = layout.repositoryCopyPath('sample');
      await Directory(repositoryCopyPath).create(recursive: true);
      await File(
        path.join(repositoryCopyPath, 'SKILL.md'),
      ).writeAsString('preserved');

      await reconciler.reconcileMaterializations(
        isolatedSkillIds: <ManagedSkillId>{ManagedSkillId(_skill)},
      );

      expect(
        await File(path.join(repositoryCopyPath, 'SKILL.md')).readAsString(),
        'preserved',
      );
      expect(revisionEngine.readPaths, isEmpty);
    },
  );

  test(
    'rebuilds a symbolic-link Activation to the Repository Copy',
    () async {
      await _insertSelection(
        database,
        activationRoot.path,
        mode: 'symbolicLink',
      );

      await reconciler.reconcileMaterializations(isolatedSkillIds: const {});

      final linkPath = path.join(activationRoot.path, 'sample');
      expect(
        await FileSystemEntity.type(linkPath, followLinks: false),
        FileSystemEntityType.link,
      );
      expect(
        path.normalize(await Link(linkPath).target()),
        path.normalize(layout.repositoryCopyPath('sample')),
      );
    },
    skip: Platform.isWindows
        ? 'Windows symbolic-link capability is validated separately.'
        : false,
  );

  test(
    'a matching symbolic-link Activation is not rebuilt',
    () async {
      await _insertSelection(
        database,
        activationRoot.path,
        mode: 'symbolicLink',
      );
      final repositoryCopyPath = layout.repositoryCopyPath('sample');
      final linkPath = path.join(activationRoot.path, 'sample');
      await _writeExpectedTree(filesystem, repositoryCopyPath);
      await activationRoot.create(recursive: true);
      await Link(linkPath).create(repositoryCopyPath);

      await reconciler.reconcileMaterializations(isolatedSkillIds: const {});

      expect(revisionEngine.readPaths, isEmpty);
      expect(
        path.normalize(await Link(linkPath).target()),
        path.normalize(repositoryCopyPath),
      );
    },
    skip: Platform.isWindows
        ? 'Windows symbolic-link capability is validated separately.'
        : false,
  );

  test(
    'a wrong symbolic-link Activation is repaired without reading the tree',
    () async {
      await _insertSelection(
        database,
        activationRoot.path,
        mode: 'symbolicLink',
      );
      final repositoryCopyPath = layout.repositoryCopyPath('sample');
      final linkPath = path.join(activationRoot.path, 'sample');
      final wrongTarget = path.join(temporary.path, 'wrong');
      await _writeExpectedTree(filesystem, repositoryCopyPath);
      await Directory(wrongTarget).create(recursive: true);
      await activationRoot.create(recursive: true);
      await Link(linkPath).create(wrongTarget);

      await reconciler.reconcileMaterializations(isolatedSkillIds: const {});

      expect(revisionEngine.readPaths, isEmpty);
      expect(
        path.normalize(await Link(linkPath).target()),
        path.normalize(repositoryCopyPath),
      );
    },
    skip: Platform.isWindows
        ? 'Windows symbolic-link capability is validated separately.'
        : false,
  );
}

Future<void> _writeExpectedTree(
  DurableWorkspaceFilesystem filesystem,
  String rootPath,
) async {
  await Directory(path.join(rootPath, 'scripts')).create(recursive: true);
  await File(path.join(rootPath, 'SKILL.md')).writeAsString('managed');
  final executable = File(path.join(rootPath, 'scripts', 'run.sh'));
  await executable.writeAsString('#!/bin/sh\n');
  await filesystem.setExecutableIntent(executable.path, _executableIntent);
}

Future<void> _insertSelection(
  WorkspaceDatabase database,
  String activationRoot, {
  required String mode,
}) {
  return database.transaction(() async {
    await database
        .into(database.managedSkills)
        .insert(
          ManagedSkillsCompanion.insert(
            id: _skill,
            slotKey: 'sample',
            declaredName: 'sample',
            displayName: 'Sample',
            description: 'Sample skill',
            activeSourceLineageId: _lineage,
            createdAtMicros: 1,
            updatedAtMicros: 1,
          ),
        );
    await database
        .into(database.sourceLineages)
        .insert(
          SourceLineagesCompanion.insert(
            id: _lineage,
            managedSkillId: _skill,
            objectFormat: 'sha1',
            createdAtMicros: 1,
          ),
        );
    await database
        .into(database.revisionMetadata)
        .insert(
          RevisionMetadataCompanion.insert(
            sourceLineageId: _lineage,
            objectId: _object,
            contentHash: _hash,
            fileCount: 2,
            byteSize: 17,
            declaredName: 'sample',
            validationState: 'valid',
            createdAtMicros: 1,
          ),
        );
    await database
        .into(database.currentRevisionSelection)
        .insert(
          CurrentRevisionSelectionCompanion.insert(
            managedSkillId: _skill,
            sourceLineageId: _lineage,
            upstreamObjectId: _object,
            effectiveObjectId: _object,
          ),
        );
    await database
        .into(database.activationLocations)
        .insert(
          ActivationLocationsCompanion.insert(
            id: _activation,
            managedSkillId: _skill,
            canonicalPath: activationRoot,
            scope: 'global',
            mode: mode,
            createdAtMicros: 1,
          ),
        );
    await database
        .into(database.activationAgents)
        .insert(
          ActivationAgentsCompanion.insert(
            activationLocationId: _activation,
            agentId: 'agent',
          ),
        );
  });
}

final class _TreeRevisionEngine implements RevisionEnginePort {
  _TreeRevisionEngine(this.tree);

  final NormalizedSkillTree tree;
  final List<String> readPaths = <String>[];

  @override
  Future<NormalizedSkillTree> readTree(
    String repositoryPath,
    RevisionObjectId commit,
  ) async {
    readPaths.add(repositoryPath);
    return tree;
  }

  @override
  Future<RevisionEngineStatus> status() async =>
      const RevisionEngineStatus(protocolVersion: 1);

  @override
  Future<void> close() async {}

  @override
  Future<void> createStore(String repositoryPath) => throw UnimplementedError();

  @override
  Future<void> verifyStore(String repositoryPath) => throw UnimplementedError();

  @override
  Future<RevisionObjectId> writeTree(
    String repositoryPath,
    NormalizedSkillTree tree,
  ) => throw UnimplementedError();

  @override
  Future<RevisionObjectId> createCommit(
    String repositoryPath,
    RevisionCommitRequest request,
  ) => throw UnimplementedError();

  @override
  Future<void> verifyCommit(
    String repositoryPath,
    RevisionObjectId commit,
    RevisionCommitRequest expected,
  ) => throw UnimplementedError();

  @override
  Future<bool> isAncestor({
    required String repositoryPath,
    required RevisionObjectId ancestor,
    required RevisionObjectId descendant,
  }) => throw UnimplementedError();

  @override
  Future<List<RevisionChange>> diff({
    required String repositoryPath,
    required RevisionObjectId oldCommit,
    required RevisionObjectId newCommit,
  }) => throw UnimplementedError();

  @override
  Future<RevisionMergeResult> merge({
    required String repositoryPath,
    required RevisionObjectId previousUpstream,
    required RevisionObjectId currentEffective,
    required RevisionObjectId incomingUpstream,
  }) => throw UnimplementedError();

  @override
  Future<void> createRecoveryPack({
    required String repositoryPath,
    required String bundleStagingPath,
    required List<RevisionObjectId> retainedRoots,
  }) => throw UnimplementedError();

  @override
  Future<void> restoreRecoveryPack({
    required String stagedRepositoryPath,
    required String packPath,
    required String indexPath,
    required List<RevisionObjectId> retainedRoots,
  }) => throw UnimplementedError();

  @override
  Future<void> replaceRetentionRefs(
    String repositoryPath,
    List<RevisionRetentionRef> references,
  ) => throw UnimplementedError();
}
