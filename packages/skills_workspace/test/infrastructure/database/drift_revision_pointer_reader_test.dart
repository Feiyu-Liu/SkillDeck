import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:path/path.dart' as path;
import 'package:skills_workspace/src/application/operations/operation_models.dart';
import 'package:skills_workspace/src/domain/identifiers.dart';
import 'package:skills_workspace/src/domain/source_descriptor.dart';
import 'package:skills_workspace/src/infrastructure/database/drift_revision_pointer_reader.dart';
import 'package:skills_workspace/src/infrastructure/database/source_descriptor_codec.dart';
import 'package:skills_workspace/src/infrastructure/database/workspace_database.dart';
import 'package:test/test.dart';

const _skill = '123e4567-e89b-42d3-a456-426614174000';
const _lineage = '123e4567-e89b-42d3-a456-426614174001';
const _otherLineage = '123e4567-e89b-42d3-a456-426614174002';
const _object = '1111111111111111111111111111111111111111';
const _otherObject = '2222222222222222222222222222222222222222';
const _hash =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

void main() {
  late Directory temporary;
  late WorkspaceDatabase database;
  late DriftRevisionPointerReader reader;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp(
      'skills-workspace-revision-pointer-',
    );
    database = WorkspaceDatabase.forFile(
      File(path.join(temporary.path, 'workspace.sqlite')),
    );
    await database.select(database.workspaceMetadata).getSingle();
    await _insertSelection(database);
    reader = DriftRevisionPointerReader(database);
  });

  tearDown(() async {
    await database.close();
    await temporary.delete(recursive: true);
  });

  test('reads active lineage-scoped Effective Pointer', () async {
    final selected = await reader.readCurrentEffective(ManagedSkillId(_skill));

    expect(selected, isNotNull);
    expect(selected!.sourceLineage, SourceLineageReference(_lineage));
    expect(selected.objectId.value, _object);
  });

  for (final sourceType in SyncedOriginSourceType.values) {
    test(
      'reads pack heads for Synced Origin with ${sourceType.name}',
      () async {
        final source = const SourceDescriptorCodec().encode(
          SyncedOriginSourceDescriptor(
            originSourceType: sourceType,
            originDeviceLabel: 'Office Mac',
            displayLabel: 'Sample Skill',
          ),
        );
        await database
            .into(database.skillSources)
            .insert(
              SkillSourcesCompanion.insert(
                sourceLineageId: _lineage,
                kind: source.kind,
                payloadSchemaVersion: source.payloadSchemaVersion,
                payloadJson: source.payloadJson,
              ),
            );

        final heads = await reader.readCurrentPackHeads(ManagedSkillId(_skill));
        expect(heads?.effective.value, _object);
        expect(
          heads?.upstream?.value,
          sourceType == SyncedOriginSourceType.adoptedSnapshot ? null : _object,
        );
        final skillId = ManagedSkillId(_skill);
        final selections = await reader.inspectRevisionSelections({skillId});
        final selection = selections.selections[skillId]!;
        expect(selection.effective.value, heads!.effective.value);
        expect(selection.upstream?.value, heads.upstream?.value);
      },
    );
  }

  test(
    'fails closed when current Pointer does not use active lineage',
    () async {
      await database.transaction(() async {
        await database
            .into(database.sourceLineages)
            .insert(
              SourceLineagesCompanion.insert(
                id: _otherLineage,
                managedSkillId: _skill,
                objectFormat: 'sha1',
                createdAtMicros: 1,
              ),
            );
        await database
            .into(database.revisionMetadata)
            .insert(
              RevisionMetadataCompanion.insert(
                sourceLineageId: _otherLineage,
                objectId: _otherObject,
                contentHash: _hash,
                fileCount: 1,
                byteSize: 1,
                declaredName: 'sample',
                validationState: 'valid',
                createdAtMicros: 1,
              ),
            );
        await database
            .update(database.currentRevisionSelection)
            .write(
              const CurrentRevisionSelectionCompanion(
                sourceLineageId: Value(_otherLineage),
                upstreamObjectId: Value(_otherObject),
                effectiveObjectId: Value(_otherObject),
              ),
            );
      });

      expect(await reader.readCurrentEffective(ManagedSkillId(_skill)), isNull);
    },
  );
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
    await database
        .into(database.revisionMetadata)
        .insert(
          RevisionMetadataCompanion.insert(
            sourceLineageId: _lineage,
            objectId: _object,
            contentHash: _hash,
            fileCount: 1,
            byteSize: 1,
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
  });
}
