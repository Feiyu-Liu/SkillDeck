import 'dart:io';

import 'package:drift/drift.dart';
import 'package:skills_workspace/src/domain/identifiers.dart';
import 'package:skills_workspace/src/domain/public_models.dart';
import 'package:skills_workspace/src/domain/source_descriptor.dart';
import 'package:skills_workspace/src/infrastructure/database/workspace_database.dart';
import 'package:skills_workspace/src/infrastructure/database/workspace_snapshot_reader.dart';
import 'package:skills_workspace/src/infrastructure/workspace_layout.dart';
import 'package:test/test.dart';

const _skillId = '123e4567-e89b-42d3-a456-426614174000';
const _lineageId = '123e4567-e89b-42d3-8456-426614174002';
const _tagId = '123e4567-e89b-42d3-a456-426614174004';
const _activationId = '123e4567-e89b-42d3-b456-426614174005';
const _objectId = '0123456789012345678901234567890123456789';
const _incomingObjectId = '1123456789012345678901234567890123456789';
const _hash =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

void main() {
  late Directory temporaryDirectory;
  late WorkspaceLayout layout;
  late WorkspaceDatabase database;
  late WorkspaceSnapshotReader reader;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'skills-workspace-snapshot-reader-',
    );
    layout = WorkspaceLayout(temporaryDirectory.path);
    database = WorkspaceDatabase.forFile(File(layout.databasePath));
    await database.workspaceMetadata.select().getSingle();
    reader = WorkspaceSnapshotReader(database: database, layout: layout);
  });

  tearDown(() async {
    await database.close();
    await temporaryDirectory.delete(recursive: true);
  });

  test('reads the initial empty control plane', () async {
    final snapshot = await reader.read();

    expect(snapshot, RepositorySnapshot.empty());
  });

  test(
    'assembles every public projection without leaking Drift rows',
    () async {
      await _insertFullProjection(database);
      final managedSkillId = ManagedSkillId(_skillId);
      final integrity = WorkspaceIntegrity(
        status: WorkspaceIntegrityStatus.recovered,
        skills: [
          ManagedSkillIntegrity(
            managedSkillId: managedSkillId,
            status: SkillIntegrityStatus.recovered,
          ),
        ],
      );

      final snapshot = await reader.readWithDraftDirtyStates(
        draftDirtyStates: {managedSkillId: true},
        integrity: integrity,
      );

      expect(snapshot.revision, RepositoryRevision(0));
      expect(snapshot.integrity, integrity);
      expect(snapshot.projectRoots.single.path, '/tmp/project');
      expect(snapshot.personalTags.single.name, 'Work');

      final skill = snapshot.managedSkills.single;
      expect(skill.id, managedSkillId);
      expect(skill.slotKey, 'reviewer');
      expect(skill.source, isA<GitSourceDescriptor>());
      expect(
        (skill.source as GitSourceDescriptor).locator,
        'https://example.com/repo.git',
      );
      expect(skill.currentRevision.contentHash, _hash);
      expect(skill.currentRevision.fileCount, 2);
      expect(skill.currentRevision.byteSize, 128);
      expect(skill.favorite.isFavorite, isTrue);
      expect(skill.favorite.changedAt?.isUtc, isTrue);
      expect(skill.note?.text, 'Important');
      expect(skill.personalTagIds, [_tagId]);
      expect(skill.activations.single.agentIds, ['claude', 'codex']);
      expect(skill.draft?.path, layout.draftPath(managedSkillId));
      expect(skill.draft?.isDirty, isTrue);
      expect(skill.updateCandidate?.status, UpdateCandidateStatus.conflicted);
      expect(skill.updateCandidate?.conflicts.single.path, 'SKILL.md');
      expect(skill.updateCandidate?.conflicts.single.kind, ConflictKind.text);
      expect(
        skill.updateCandidate?.conflicts.single.resolutionState,
        UpdateConflictResolutionState.unresolved,
      );
    },
  );
}

Future<void> _insertFullProjection(WorkspaceDatabase database) async {
  const createdAt = 1_000_000;
  await database.transaction(() async {
    await database
        .into(database.managedSkills)
        .insert(
          ManagedSkillsCompanion.insert(
            id: _skillId,
            slotKey: 'reviewer',
            declaredName: 'reviewer',
            displayName: 'Reviewer',
            description: 'Reviews Skills.',
            activeSourceLineageId: _lineageId,
            createdAtMicros: createdAt,
            updatedAtMicros: createdAt,
          ),
        );
    await database
        .into(database.sourceLineages)
        .insert(
          SourceLineagesCompanion.insert(
            id: _lineageId,
            managedSkillId: _skillId,
            objectFormat: 'sha1',
            createdAtMicros: createdAt,
          ),
        );
    await database
        .into(database.skillSources)
        .insert(
          SkillSourcesCompanion.insert(
            sourceLineageId: _lineageId,
            kind: 'git',
            payloadSchemaVersion: currentSourcePayloadSchemaVersion,
            payloadJson: '{"locator":"https://example.com/repo.git"}',
          ),
        );
    await database
        .into(database.revisionMetadata)
        .insert(
          RevisionMetadataCompanion.insert(
            sourceLineageId: _lineageId,
            objectId: _objectId,
            contentHash: _hash,
            fileCount: 2,
            byteSize: 128,
            declaredName: 'reviewer',
            validationState: 'valid',
            createdAtMicros: createdAt,
          ),
        );
    await database
        .into(database.revisionMetadata)
        .insert(
          RevisionMetadataCompanion.insert(
            sourceLineageId: _lineageId,
            objectId: _incomingObjectId,
            contentHash:
                'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
            fileCount: 2,
            byteSize: 130,
            declaredName: 'reviewer',
            validationState: 'valid',
            createdAtMicros: createdAt + 1,
          ),
        );
    await database
        .into(database.currentRevisionSelection)
        .insert(
          CurrentRevisionSelectionCompanion.insert(
            managedSkillId: _skillId,
            sourceLineageId: _lineageId,
            upstreamObjectId: _objectId,
            effectiveObjectId: _objectId,
          ),
        );
  });

  await database
      .into(database.projectRoots)
      .insert(
        ProjectRootsCompanion.insert(
          id: 'project',
          canonicalPath: '/tmp/project',
          createdAtMicros: createdAt,
          updatedAtMicros: createdAt,
        ),
      );
  await database
      .into(database.activationLocations)
      .insert(
        ActivationLocationsCompanion.insert(
          id: _activationId,
          managedSkillId: _skillId,
          canonicalPath: '/tmp/activation/reviewer',
          scope: 'global',
          mode: 'copy',
          createdAtMicros: createdAt,
        ),
      );
  for (final agentId in ['codex', 'claude']) {
    await database
        .into(database.activationAgents)
        .insert(
          ActivationAgentsCompanion.insert(
            activationLocationId: _activationId,
            agentId: agentId,
          ),
        );
  }
  await database
      .into(database.skillUserData)
      .insert(
        SkillUserDataCompanion.insert(
          managedSkillId: _skillId,
          favorite: const Value(true),
          favoriteChangedAtMicros: const Value(createdAt),
          note: const Value('Important'),
          noteUpdatedAtMicros: const Value(createdAt),
        ),
      );
  await database
      .into(database.personalTags)
      .insert(
        PersonalTagsCompanion.insert(
          id: _tagId,
          normalizedKey: 'work',
          displayName: 'Work',
          color: const Value('#FFCC00'),
          createdAtMicros: createdAt,
          updatedAtMicros: createdAt,
        ),
      );
  await database
      .into(database.skillTagAssignments)
      .insert(
        SkillTagAssignmentsCompanion.insert(
          managedSkillId: _skillId,
          personalTagId: _tagId,
          createdAtMicros: createdAt,
        ),
      );
  await database
      .into(database.draftWorkspaces)
      .insert(
        DraftWorkspacesCompanion.insert(
          managedSkillId: _skillId,
          sourceLineageId: _lineageId,
          baseObjectId: _objectId,
          purpose: 'customization',
          createdAtMicros: createdAt,
          updatedAtMicros: createdAt,
        ),
      );
  await database
      .into(database.updateCandidateSessions)
      .insert(
        UpdateCandidateSessionsCompanion.insert(
          managedSkillId: _skillId,
          sourceLineageId: _lineageId,
          previousUpstreamObjectId: _objectId,
          previousEffectiveObjectId: _objectId,
          incomingUpstreamObjectId: _incomingObjectId,
          candidateObjectId: 'candidate-tree',
          status: 'conflicted',
          createdAtMicros: createdAt,
          updatedAtMicros: createdAt,
        ),
      );
  await database
      .into(database.updateCandidateItems)
      .insert(
        UpdateCandidateItemsCompanion.insert(
          managedSkillId: _skillId,
          path: 'SKILL.md',
          kind: 'text',
          state: 'unresolved',
        ),
      );
}
