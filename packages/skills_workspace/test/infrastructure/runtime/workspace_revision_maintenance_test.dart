import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:skills_workspace/src/application/operations/operation_models.dart';
import 'package:skills_workspace/src/application/ports/workspace_lifecycle_ports.dart';
import 'package:skills_workspace/src/application/runtime/revision_engine_port.dart';
import 'package:skills_workspace/src/domain/identifiers.dart';
import 'package:skills_workspace/src/domain/revision_content.dart';
import 'package:skills_workspace/src/infrastructure/database/workspace_database.dart';
import 'package:skills_workspace/src/composition/workspace_revision_maintenance.dart';
import 'package:skills_workspace/src/infrastructure/workspace_layout.dart';
import 'package:skills_workspace/src/native/revision_engine/revision_recovery_bundle.dart';
import 'package:skills_workspace/src/platform/filesystem/durable_workspace_filesystem.dart';
import 'package:test/test.dart';

const _skill = '123e4567-e89b-42d3-a456-426614174000';
const _lineage = '123e4567-e89b-42d3-a456-426614174001';
const _upstream = '1111111111111111111111111111111111111111';
const _effective = '2222222222222222222222222222222222222222';
const _hash =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

void main() {
  late Directory temporary;
  late WorkspaceLayout layout;
  late WorkspaceDatabase database;
  late _MarkerRevisionEngine revisionEngine;
  late DriftWorkspaceRevisionMaintenance maintenance;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp(
      'skills-workspace-revision-maintenance-',
    );
    layout = WorkspaceLayout(temporary.path);
    database = WorkspaceDatabase.forFile(File(layout.databasePath));
    await database.select(database.workspaceMetadata).getSingle();
    await _insertSelection(database);
    revisionEngine = _MarkerRevisionEngine();
    maintenance = DriftWorkspaceRevisionMaintenance(
      database: database,
      layout: layout,
      revisionEngine: revisionEngine,
      filesystem: PlatformDurableWorkspaceFilesystem(),
    );
  });

  tearDown(() async {
    await database.close();
    await temporary.delete(recursive: true);
  });

  test('reads complete active selections in deterministic order', () async {
    final selections = await maintenance.selectedRevisions();

    expect(selections, hasLength(1));
    final selected = selections.single as DriftWorkspaceSelectedRevision;
    expect(selected.managedSkillId.value, _skill);
    expect(selected.sourceLineage, SourceLineageReference(_lineage));
    expect(selected.currentUpstream, RevisionObjectId(_upstream));
    expect(selected.currentEffective, RevisionObjectId(_effective));
  });

  test('reports a readable selected Store as healthy', () async {
    final selected =
        (await maintenance.selectedRevisions()).single
            as DriftWorkspaceSelectedRevision;
    final storePath = layout.revisionStorePath(selected.managedSkillId);
    await revisionEngine.makeHealthy(storePath);

    final result = await maintenance.validateOrRecover(selected);

    expect(result.disposition, WorkspaceRevisionMaintenanceDisposition.healthy);
    expect(revisionEngine.restoredPaths, isEmpty);
    expect(revisionEngine.verifiedPaths, [storePath]);
    expect(revisionEngine.readCommits, [
      RevisionObjectId(_upstream),
      RevisionObjectId(_effective),
    ]);
  });

  test(
    'identical upstream and Effective pointers read one authoritative tree',
    () async {
      final selected =
          (await maintenance.selectedRevisions()).single
              as DriftWorkspaceSelectedRevision;
      final storePath = layout.revisionStorePath(selected.managedSkillId);
      await revisionEngine.makeHealthy(storePath);
      final result = await maintenance.validateOrRecover(
        DriftWorkspaceSelectedRevision(
          managedSkillId: selected.managedSkillId,
          sourceLineage: selected.sourceLineage,
          currentUpstream: selected.currentUpstream,
          currentEffective: selected.currentUpstream,
        ),
      );
      expect(
        result.disposition,
        WorkspaceRevisionMaintenanceDisposition.healthy,
      );
      expect(revisionEngine.verifiedPaths, [storePath]);
      expect(revisionEngine.readCommits, [RevisionObjectId(_upstream)]);
      expect(revisionEngine.restoredPaths, isEmpty);
    },
  );

  test('restores a corrupt Store only from its matching Bundle', () async {
    final selected =
        (await maintenance.selectedRevisions()).single
            as DriftWorkspaceSelectedRevision;
    final storePath = layout.revisionStorePath(selected.managedSkillId);
    await Directory(storePath).create(recursive: true);
    await File(path.join(storePath, 'corrupt')).writeAsString('bad');
    await _writeBundle(layout);

    final result = await maintenance.validateOrRecover(selected);

    expect(
      result.disposition,
      WorkspaceRevisionMaintenanceDisposition.recoveredFromBundle,
    );
    expect(revisionEngine.restoredPaths, hasLength(1));
    expect(await File(path.join(storePath, '.healthy')).exists(), isTrue);
    expect(await File(path.join(storePath, 'corrupt')).exists(), isFalse);
  });

  test('isolates the Skill when Bundle identity does not match', () async {
    final selected =
        (await maintenance.selectedRevisions()).single
            as DriftWorkspaceSelectedRevision;
    await _writeBundle(
      layout,
      sourceLineageId: '123e4567-e89b-42d3-a456-426614174099',
    );

    final result = await maintenance.validateOrRecover(selected);

    expect(
      result.disposition,
      WorkspaceRevisionMaintenanceDisposition.isolatedCorrupt,
    );
    expect(revisionEngine.restoredPaths, isEmpty);
  });

  final corruptBundleCases =
      <({String name, Future<void> Function(String bundlePath) mutate})>[
        (
          name: 'manifest is missing',
          mutate: (bundlePath) =>
              File(path.join(bundlePath, 'manifest.json')).delete(),
        ),
        (
          name: 'manifest is corrupt',
          mutate: (bundlePath) => File(
            path.join(bundlePath, 'manifest.json'),
          ).writeAsString('{not-json', flush: true),
        ),
        (
          name: 'completion fence is missing',
          mutate: (bundlePath) =>
              File(path.join(bundlePath, 'COMPLETE')).delete(),
        ),
        (
          name: 'completion fence is corrupt',
          mutate: (bundlePath) => File(
            path.join(bundlePath, 'COMPLETE'),
          ).writeAsString('{not-json', flush: true),
        ),
        (
          name: 'pack is missing',
          mutate: (bundlePath) =>
              File(path.join(bundlePath, 'objects.pack')).delete(),
        ),
        (
          name: 'pack is corrupt',
          mutate: (bundlePath) => File(
            path.join(bundlePath, 'objects.pack'),
          ).writeAsBytes(const <int>[9, 9, 9], flush: true),
        ),
        (
          name: 'index is missing',
          mutate: (bundlePath) =>
              File(path.join(bundlePath, 'objects.idx')).delete(),
        ),
        (
          name: 'index is corrupt',
          mutate: (bundlePath) => File(
            path.join(bundlePath, 'objects.idx'),
          ).writeAsBytes(const <int>[8, 8, 8], flush: true),
        ),
      ];
  for (final corruptBundleCase in corruptBundleCases) {
    test('isolates the Skill when Bundle ${corruptBundleCase.name}', () async {
      final selected =
          (await maintenance.selectedRevisions()).single
              as DriftWorkspaceSelectedRevision;
      await _writeBundle(layout);
      await corruptBundleCase.mutate(_bundlePath(layout));

      final result = await maintenance.validateOrRecover(selected);

      expect(
        result.disposition,
        WorkspaceRevisionMaintenanceDisposition.isolatedCorrupt,
      );
      expect(revisionEngine.restoredPaths, isEmpty);
    });
  }
}

Future<void> _insertSelection(WorkspaceDatabase database) {
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
    for (final objectId in <String>[_upstream, _effective]) {
      await database
          .into(database.revisionMetadata)
          .insert(
            RevisionMetadataCompanion.insert(
              sourceLineageId: _lineage,
              objectId: objectId,
              contentHash: _hash,
              fileCount: 1,
              byteSize: 1,
              declaredName: 'sample',
              validationState: 'valid',
              createdAtMicros: 1,
            ),
          );
    }
    await database
        .into(database.currentRevisionSelection)
        .insert(
          CurrentRevisionSelectionCompanion.insert(
            managedSkillId: _skill,
            sourceLineageId: _lineage,
            upstreamObjectId: _upstream,
            effectiveObjectId: _effective,
          ),
        );
  });
}

Future<void> _writeBundle(
  WorkspaceLayout layout, {
  String sourceLineageId = _lineage,
}) async {
  const codec = RevisionRecoveryBundleCodec();
  final pack = <int>[1, 2, 3];
  final index = <int>[4, 5, 6];
  final manifest = codec.createManifest(
    sourceLineageId: sourceLineageId,
    currentUpstream: RevisionObjectId(_upstream),
    currentEffective: RevisionObjectId(_effective),
    retainedPublishedRoots: <RevisionObjectId>[
      RevisionObjectId(_upstream),
      RevisionObjectId(_effective),
    ],
    packBytes: pack,
    indexBytes: index,
  );
  final manifestBytes = codec.encodeManifest(manifest);
  final bundlePath = _bundlePath(layout);
  await Directory(bundlePath).create(recursive: true);
  await File(
    path.join(bundlePath, 'manifest.json'),
  ).writeAsBytes(manifestBytes);
  await File(path.join(bundlePath, 'objects.pack')).writeAsBytes(pack);
  await File(path.join(bundlePath, 'objects.idx')).writeAsBytes(index);
  await File(
    path.join(bundlePath, 'COMPLETE'),
  ).writeAsBytes(codec.createCompletionFence(manifestBytes));
}

String _bundlePath(WorkspaceLayout layout) =>
    layout.revisionBundlePath(ManagedSkillId(_skill));

final class _MarkerRevisionEngine implements RevisionEnginePort {
  final List<String> restoredPaths = <String>[];
  final List<String> verifiedPaths = <String>[];
  final List<RevisionObjectId> readCommits = <RevisionObjectId>[];

  Future<void> makeHealthy(String repositoryPath) async {
    await Directory(repositoryPath).create(recursive: true);
    await File(path.join(repositoryPath, '.healthy')).writeAsString('ok');
  }

  @override
  Future<void> verifyStore(String repositoryPath) async {
    verifiedPaths.add(repositoryPath);
    await _requireHealthy(repositoryPath);
  }

  Future<void> _requireHealthy(String repositoryPath) async {
    if (!await File(path.join(repositoryPath, '.healthy')).exists()) {
      throw const RevisionEngineException(
        RevisionEngineFailureCode.verificationFailed,
      );
    }
  }

  @override
  Future<NormalizedSkillTree> readTree(
    String repositoryPath,
    RevisionObjectId commit,
  ) async {
    readCommits.add(commit);
    await _requireHealthy(repositoryPath);
    return NormalizedSkillTree(
      files: const [],
      contentHash: _hash,
      byteSize: 0,
    );
  }

  @override
  Future<void> restoreRecoveryPack({
    required String stagedRepositoryPath,
    required String packPath,
    required String indexPath,
    required List<RevisionObjectId> retainedRoots,
  }) async {
    restoredPaths.add(stagedRepositoryPath);
    await makeHealthy(stagedRepositoryPath);
  }

  @override
  Future<void> replaceRetentionRefs(
    String repositoryPath,
    List<RevisionRetentionRef> references,
  ) => throw UnimplementedError();

  @override
  Future<RevisionEngineStatus> status() async =>
      const RevisionEngineStatus(protocolVersion: 1);

  @override
  Future<void> close() async {}

  @override
  Future<void> createStore(String repositoryPath) => throw UnimplementedError();

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
}
