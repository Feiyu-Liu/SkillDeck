import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:path/path.dart' as path;
import 'package:skills_workspace/src/application/operations/destructive_recovery_intent.dart';
import 'package:skills_workspace/src/application/operations/operation_models.dart';
import 'package:skills_workspace/src/application/operations/workspace_business_changes.dart';
import 'package:skills_workspace/src/application/runtime/revision_engine_port.dart';
import 'package:skills_workspace/src/composition/destructive_recovery_entries.dart';
import 'package:skills_workspace/src/composition/revision_worker_task_executor.dart';
import 'package:skills_workspace/src/domain/cancellation.dart';
import 'package:skills_workspace/src/domain/identifiers.dart';
import 'package:skills_workspace/src/infrastructure/content/normalized_skill_tree.dart';
import 'package:skills_workspace/src/infrastructure/database/workspace_database.dart';
import 'package:skills_workspace/src/infrastructure/workspace_layout.dart';
import 'package:skills_workspace/src/native/revision_worker/revision_worker_runtime.dart';
import 'package:skills_workspace/src/platform/filesystem/durable_workspace_filesystem.dart';
import 'package:skills_workspace/src/platform/operations/operation_recovery_bundle.dart';
import 'package:test/test.dart';

void main() {
  late Directory temporaryDirectory;
  late WorkspaceLayout layout;
  late WorkspaceDatabase database;
  late RevisionWorkerRuntime revisions;
  late OperationRecoverySpecRegistry registry;
  late WorkspaceDestructiveRecoveryEntries entries;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'skills-workspace-destructive-entries-',
    );
    layout = WorkspaceLayout(path.join(temporaryDirectory.path, 'workspace'));
    database = WorkspaceDatabase.forFile(File(layout.databasePath));
    await database.workspaceMetadata.select().getSingle();
    await _seed(database);
    revisions = RevisionWorkerRuntime(
      taskExecutor: executeComposedRevisionWorkerTask,
    );
    await revisions.start();
    registry = OperationRecoverySpecRegistry();
    entries = WorkspaceDestructiveRecoveryEntries(
      database: database,
      layout: layout,
      revisions: revisions,
      filesystem: PlatformDurableWorkspaceFilesystem(),
      recoverySpecs: registry,
    );
  });

  tearDown(() async {
    await revisions.close();
    await database.close();
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test(
    'Source Replacement stages complete old and new path transitions',
    () async {
      final candidateStore = layout.operationSourceReplacementStore(
        _operationId,
      );
      final candidateBundle = layout.operationSourceReplacementBundle(
        _operationId,
      );
      await revisions.createStore(candidateStore);
      final tree = const SkillContentNormalizer().normalize(<SkillContentEntry>[
        SkillContentEntry.file(
          path: 'SKILL.md',
          bytes: const [1, 2, 3],
          isExecutable: false,
        ),
      ]).valueOrNull!;
      final treeObject = await revisions.writeTree(candidateStore, tree);
      final request = RevisionCommitRequest(
        tree: treeObject,
        parents: const [],
        kind: RevisionCommitKind.initial,
      );
      final commit = await revisions.createCommit(candidateStore, request);
      await Directory(candidateBundle).create(recursive: true);
      await File(path.join(candidateBundle, 'marker')).writeAsString('bundle');

      await entries.prepareRecoveryEntries(
        operationId: _operationId,
        intent: SourceReplacementRecoveryIntent(
          skill: _skillIntent(hasDraft: true),
          intendedSourceLineage: _newLineage,
          intendedSlotKey: 'replacement',
          intendedObjectId: commit,
          intendedContentHash: 'a' * 64,
          intendedObjectFormat: WorkspaceObjectFormat.sha1,
        ),
        cancellationToken: CancellationToken.none(),
      );

      final staged = registry.takeDestructiveEntries(_operationId);
      final byTarget = <String, OperationRecoveryEntrySpec>{
        for (final entry in staged) path.normalize(entry.targetPath): entry,
      };
      final newRepository = layout.repositoryCopyPath('replacement');
      expect(
        byTarget[path.normalize(layout.repositoryCopyPath('current'))]
            ?.intendedKind,
        isNull,
      );
      expect(
        byTarget[path.normalize(newRepository)]?.intendedKind,
        OperationRecoveryEntryKind.directory,
      );
      expect(
        byTarget[path.normalize(path.join(_agentRoot, 'current'))]
            ?.intendedKind,
        isNull,
      );
      final newActivation =
          byTarget[path.normalize(path.join(_agentRoot, 'replacement'))]!;
      expect(
        newActivation.intendedKind,
        OperationRecoveryEntryKind.symbolicLink,
      );
      expect(newActivation.intendedSymbolicLinkTarget, newRepository);
      expect(
        byTarget[path.normalize(layout.draftPath(_skillId))]?.intendedKind,
        isNull,
      );
      expect(
        byTarget[path.normalize(layout.revisionStorePath(_skillId))]
            ?.intendedSourcePath,
        candidateStore,
      );
      expect(
        await File(
          path.join(
            layout.operationSourceReplacementRoot(_operationId),
            'tree',
            'SKILL.md',
          ),
        ).exists(),
        isTrue,
      );
    },
  );

  test('Removal stages only absence for every managed path', () async {
    await entries.prepareRecoveryEntries(
      operationId: _operationId,
      intent: RemovalRecoveryIntent(skills: [_skillIntent(hasDraft: true)]),
      cancellationToken: CancellationToken.none(),
    );

    final staged = registry.takeDestructiveEntries(_operationId);
    expect(staged, hasLength(5));
    expect(staged.every((entry) => entry.intendedKind == null), isTrue);
    expect(
      staged.map((entry) => path.normalize(entry.targetPath)),
      containsAll(<String>[
        path.normalize(layout.revisionStorePath(_skillId)),
        path.normalize(layout.revisionBundlePath(_skillId)),
        path.normalize(layout.repositoryCopyPath('current')),
        path.normalize(path.join(_agentRoot, 'current')),
        path.normalize(layout.draftPath(_skillId)),
      ]),
    );
  });
}

Future<void> _seed(WorkspaceDatabase database) =>
    database.transaction(() async {
      await database
          .into(database.managedSkills)
          .insert(
            ManagedSkillsCompanion.insert(
              id: _skillId.value,
              slotKey: 'current',
              declaredName: 'current',
              displayName: 'Current',
              description: 'Current Skill',
              activeSourceLineageId: _oldLineage.encoded,
              createdAtMicros: 1,
              updatedAtMicros: 1,
            ),
          );
      await database
          .into(database.sourceLineages)
          .insert(
            SourceLineagesCompanion.insert(
              id: _oldLineage.encoded,
              managedSkillId: _skillId.value,
              objectFormat: 'sha1',
              createdAtMicros: 1,
            ),
          );
      await database
          .into(database.activationLocations)
          .insert(
            ActivationLocationsCompanion.insert(
              id: _activationId,
              managedSkillId: _skillId.value,
              canonicalPath: _agentRoot,
              scope: 'global',
              mode: 'symbolicLink',
              createdAtMicros: 1,
            ),
          );
    });

DestructiveSkillRecoveryIntent _skillIntent({required bool hasDraft}) =>
    DestructiveSkillRecoveryIntent(
      managedSkillId: _skillId,
      slotKey: 'current',
      sourceLineages: [RecoverySourceLineageIntent(sourceLineage: _oldLineage)],
      activationIds: const [_activationId],
      hasDraft: hasDraft,
      hasUpdateCandidateSession: false,
    );

final _operationId = OperationId('123e4567-e89b-42d3-a456-426614174020');
final _agentRoot = path.normalize(path.absolute('agents'));
final _skillId = ManagedSkillId('123e4567-e89b-42d3-a456-426614174000');
final _oldLineage = SourceLineageReference(
  '123e4567-e89b-42d3-8456-426614174001',
);
final _newLineage = SourceLineageReference(
  '123e4567-e89b-42d3-8456-426614174002',
);
const _activationId = '123e4567-e89b-42d3-8456-426614174010';
