import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as path;
import 'package:skills_workspace/src/domain/identifiers.dart';
import 'package:skills_workspace/src/domain/public_models.dart';
import 'package:skills_workspace/src/infrastructure/database/drift_activation_metadata_reader.dart';
import 'package:skills_workspace/src/infrastructure/database/workspace_database.dart';
import 'package:test/test.dart';

void main() {
  late Directory temporary;
  late WorkspaceDatabase database;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp(
      'activation-metadata-reader-',
    );
    database = WorkspaceDatabase.forFile(
      File(path.join(temporary.path, 'workspace.sqlite')),
      busyTimeout: const Duration(seconds: 1),
    );
    await database.workspaceMetadata.select().getSingle();
    await _insertSkill(database, _skillId, _lineageId);
  });

  tearDown(() async {
    await database.close();
    await temporary.delete(recursive: true);
  });

  test(
    'maps Activation identity, provenance, mode and sorted agents',
    () async {
      await database
          .into(database.activationLocations)
          .insert(
            ActivationLocationsCompanion.insert(
              id: _activationId,
              managedSkillId: _skillId,
              canonicalPath: '/workspace/.agents/skills',
              scope: 'project',
              mode: 'copy',
              projectRootId: const Value('project'),
              projectRootPath: const Value('/workspace'),
              createdAtMicros: 42,
            ),
          );
      await database
          .into(database.activationAgents)
          .insert(
            ActivationAgentsCompanion.insert(
              activationLocationId: _activationId,
              agentId: 'zeta',
            ),
          );
      await database
          .into(database.activationAgents)
          .insert(
            ActivationAgentsCompanion.insert(
              activationLocationId: _activationId,
              agentId: 'alpha',
            ),
          );

      final values = await DriftActivationMetadataReader(
        database: database,
      ).readForSkills(<ManagedSkillId>{ManagedSkillId(_skillId)});

      expect(values, hasLength(1));
      expect(values.single.activationId, _activationId);
      expect(values.single.createdAtMicros, 42);
      expect(values.single.managedSkillId, ManagedSkillId(_skillId));
      expect(values.single.activation.scope, ActivationScope.project);
      expect(values.single.activation.mode, ActivationMode.copy);
      expect(values.single.activation.agentIds, <String>['alpha', 'zeta']);
      expect(values.single.activation.projectRootId, 'project');
      expect(values.single.activation.projectRootPath, '/workspace');
    },
  );

  test('filters requested Skills and returns immutable values', () async {
    final reader = DriftActivationMetadataReader(database: database);

    expect(await reader.readForSkills(<ManagedSkillId>{}), isEmpty);
    expect(
      await reader.readForSkills(<ManagedSkillId>{
        ManagedSkillId(_otherSkillId),
      }),
      isEmpty,
    );
  });
}

Future<void> _insertSkill(
  WorkspaceDatabase database,
  String skillId,
  String lineageId,
) => database.transaction(() async {
  await database
      .into(database.managedSkills)
      .insert(
        ManagedSkillsCompanion.insert(
          id: skillId,
          slotKey: 'example',
          declaredName: 'example',
          displayName: 'Example',
          description: 'Example Skill',
          activeSourceLineageId: lineageId,
          createdAtMicros: 1,
          updatedAtMicros: 1,
        ),
      );
  await database
      .into(database.sourceLineages)
      .insert(
        SourceLineagesCompanion.insert(
          id: lineageId,
          managedSkillId: skillId,
          objectFormat: 'sha1',
          createdAtMicros: 1,
        ),
      );
  await database
      .into(database.skillSources)
      .insert(
        SkillSourcesCompanion.insert(
          sourceLineageId: lineageId,
          kind: 'local',
          payloadSchemaVersion: 1,
          payloadJson: '{"locator":"/source"}',
        ),
      );
  await database
      .into(database.revisionMetadata)
      .insert(
        RevisionMetadataCompanion.insert(
          sourceLineageId: lineageId,
          objectId: _objectId,
          contentHash: 'a' * 64,
          fileCount: 1,
          byteSize: 1,
          declaredName: 'example',
          validationState: 'valid',
          validationCode: const Value(null),
          createdAtMicros: 1,
        ),
      );
  await database
      .into(database.currentRevisionSelection)
      .insert(
        CurrentRevisionSelectionCompanion.insert(
          managedSkillId: skillId,
          sourceLineageId: lineageId,
          upstreamObjectId: _objectId,
          effectiveObjectId: _objectId,
        ),
      );
});

const _skillId = '123e4567-e89b-42d3-a456-426614174400';
const _otherSkillId = '123e4567-e89b-42d3-b456-426614174401';
const _lineageId = '123e4567-e89b-42d3-8456-426614174402';
const _activationId = '123e4567-e89b-42d3-9456-426614174403';
const _objectId = '0123456789012345678901234567890123456789';
