import 'dart:io';

import 'package:drift/drift.dart';
import 'package:skills_workspace/src/infrastructure/database/workspace_database.dart';
import 'package:test/test.dart';

const _skillId = '123e4567-e89b-42d3-a456-426614174000';
const _secondSkillId = '123e4567-e89b-42d3-b456-426614174001';
const _lineageId = '123e4567-e89b-42d3-8456-426614174002';
const _secondLineageId = '123e4567-e89b-42d3-9456-426614174003';
const _tagId = '123e4567-e89b-42d3-a456-426614174004';
const _activationId = '123e4567-e89b-42d3-b456-426614174005';
const _secondActivationId = '123e4567-e89b-42d3-8456-426614174008';
const _thirdActivationId = '123e4567-e89b-42d3-9456-426614174009';
const _operationId = '123e4567-e89b-42d3-8456-426614174006';
const _subjectId = '123e4567-e89b-42d3-9456-426614174007';
const _objectId = '0123456789012345678901234567890123456789';
const _incomingObjectId = '1123456789012345678901234567890123456789';
const _hash =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

void main() {
  late Directory temporaryDirectory;
  late WorkspaceDatabase database;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'skills-workspace-db-',
    );
    database = WorkspaceDatabase.forFile(
      File('${temporaryDirectory.path}/workspace.sqlite'),
      busyTimeout: const Duration(milliseconds: 1234),
    );
    await database.workspaceMetadata.select().getSingle();
  });

  tearDown(() async {
    await database.close();
    await temporaryDirectory.delete(recursive: true);
  });

  test(
    'creates schema v3 with the required SQLite durability pragmas',
    () async {
      expect(await _pragma(database, 'journal_mode'), 'wal');
      expect(await _pragma(database, 'synchronous'), 2);
      expect(await _pragma(database, 'foreign_keys'), 1);
      expect(await _pragma(database, 'busy_timeout'), 1234);

      final metadata = await database.workspaceMetadata.select().getSingle();
      expect(metadata.singleton, 1);
      expect(metadata.repositoryRevision, 0);
      expect(metadata.destructionEpoch, 0);
    },
  );

  test('deferred lineage ownership permits one atomic cyclic insert', () async {
    await _insertSkillGraph(database);

    final skill = await database.managedSkills.select().getSingle();
    final lineage = await database.sourceLineages.select().getSingle();
    final selection = await database.currentRevisionSelection
        .select()
        .getSingle();
    expect(skill.activeSourceLineageId, lineage.id);
    expect(lineage.managedSkillId, skill.id);
    expect(selection.sourceLineageId, lineage.id);
  });

  test(
    'primary, unique, check, payload, and foreign-key constraints fail closed',
    () async {
      await _insertSkillGraph(database);

      await database.delete(database.skillSources).go();
      await expectLater(
        database
            .into(database.skillSources)
            .insert(
              SkillSourcesCompanion.insert(
                sourceLineageId: _lineageId,
                kind: 'unknown',
                payloadSchemaVersion: 1,
                payloadJson: '{}',
              ),
            ),
        throwsA(anything),
      );
      await expectLater(
        database
            .into(database.skillSources)
            .insert(
              SkillSourcesCompanion.insert(
                sourceLineageId: _lineageId,
                kind: 'git',
                payloadSchemaVersion: 2,
                payloadJson: '{}',
              ),
            ),
        throwsA(anything),
      );
      await expectLater(
        database
            .into(database.skillSources)
            .insert(
              SkillSourcesCompanion.insert(
                sourceLineageId: _lineageId,
                kind: 'git',
                payloadSchemaVersion: 1,
                payloadJson: 'not-json',
              ),
            ),
        throwsA(anything),
      );
      await expectLater(
        database
            .into(database.activationAgents)
            .insert(
              ActivationAgentsCompanion.insert(
                activationLocationId: _activationId,
                agentId: 'claude',
              ),
            ),
        throwsA(anything),
      );
      await expectLater(
        _insertSkillGraph(
          database,
          skillId: _secondSkillId,
          lineageId: _secondLineageId,
          slotKey: 'reviewer',
        ),
        throwsA(anything),
      );
      await expectLater(
        database
            .into(database.revisionMetadata)
            .insert(
              RevisionMetadataCompanion.insert(
                sourceLineageId: _lineageId,
                objectId: 'invalid-hash-revision',
                contentHash: 'INVALID',
                fileCount: -1,
                byteSize: -1,
                declaredName: '',
                validationState: 'unknown',
                createdAtMicros: -1,
              ),
            ),
        throwsA(anything),
      );

      await _insertSkillGraph(
        database,
        skillId: _secondSkillId,
        lineageId: _secondLineageId,
        slotKey: 'reviewer-two',
      );
      final now = DateTime.now().toUtc().microsecondsSinceEpoch;
      await expectLater(
        database
            .into(database.draftWorkspaces)
            .insert(
              DraftWorkspacesCompanion.insert(
                managedSkillId: _skillId,
                sourceLineageId: _secondLineageId,
                baseObjectId: _objectId,
                purpose: 'customization',
                createdAtMicros: now,
                updatedAtMicros: now,
              ),
            ),
        throwsA(anything),
      );

      expect(await database.managedSkills.select().get(), hasLength(2));
    },
  );

  test('one Draft and one Update Candidate exist per managed Skill', () async {
    await _insertSkillGraph(database, includeIncomingRevision: true);
    final now = DateTime.now().toUtc().microsecondsSinceEpoch;
    final draft = DraftWorkspacesCompanion.insert(
      managedSkillId: _skillId,
      sourceLineageId: _lineageId,
      baseObjectId: _objectId,
      purpose: 'customization',
      createdAtMicros: now,
      updatedAtMicros: now,
    );
    await database.into(database.draftWorkspaces).insert(draft);
    await expectLater(
      database.into(database.draftWorkspaces).insert(draft),
      throwsA(anything),
    );

    final session = UpdateCandidateSessionsCompanion.insert(
      managedSkillId: _skillId,
      sourceLineageId: _lineageId,
      previousUpstreamObjectId: _objectId,
      previousEffectiveObjectId: _objectId,
      incomingUpstreamObjectId: _incomingObjectId,
      candidateObjectId: 'candidate-tree',
      status: 'conflicted',
      createdAtMicros: now,
      updatedAtMicros: now,
    );
    await database.into(database.updateCandidateSessions).insert(session);
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
    await expectLater(
      database.into(database.updateCandidateSessions).insert(session),
      throwsA(anything),
    );
  });

  test(
    'revision-guarded transaction is consistent and rejects stale callers',
    () async {
      await database.transactionAtRevision(0, () async {
        final withinTransaction = await database.workspaceMetadata
            .select()
            .getSingle();
        expect(withinTransaction.repositoryRevision, 0);
        await database
            .into(database.personalTags)
            .insert(
              PersonalTagsCompanion.insert(
                id: _tagId,
                normalizedKey: 'work',
                displayName: 'Work',
                createdAtMicros: 1,
                updatedAtMicros: 1,
              ),
            );
      });

      expect(
        (await database.workspaceMetadata.select().getSingle())
            .repositoryRevision,
        1,
      );
      await expectLater(
        database.transactionAtRevision(0, () async {
          await database.customStatement('DELETE FROM personal_tags');
        }),
        throwsA(
          isA<StaleControlPlaneRevision>()
              .having((error) => error.expected, 'expected', 0)
              .having((error) => error.actual, 'actual', 1),
        ),
      );
      expect(await database.personalTags.select().get(), hasLength(1));
    },
  );

  test(
    'Removal cascades per-Skill state but preserves tags and Journal evidence',
    () async {
      await _insertSkillGraph(database, includeIncomingRevision: true);
      await _insertEveryPerSkillProjection(database);

      await (database.delete(
        database.managedSkills,
      )..where((row) => row.id.equals(_skillId))).go();

      expect(await database.managedSkills.select().get(), isEmpty);
      expect(await database.sourceLineages.select().get(), isEmpty);
      expect(await database.skillSources.select().get(), isEmpty);
      expect(await database.revisionMetadata.select().get(), isEmpty);
      expect(await database.currentRevisionSelection.select().get(), isEmpty);
      expect(await database.draftWorkspaces.select().get(), isEmpty);
      expect(await database.updateCandidateSessions.select().get(), isEmpty);
      expect(await database.updateCandidateItems.select().get(), isEmpty);
      expect(await database.activationLocations.select().get(), isEmpty);
      expect(await database.activationAgents.select().get(), isEmpty);
      expect(await database.skillUserData.select().get(), isEmpty);
      expect(await database.skillTagAssignments.select().get(), isEmpty);
      expect(await database.operationSubjects.select().get(), isEmpty);
      expect(await database.operationRecords.select().get(), isEmpty);

      expect(await database.personalTags.select().get(), hasLength(1));
      expect(await database.operationJournals.select().get(), hasLength(1));
      expect(await database.operationJournalSteps.select().get(), hasLength(1));
    },
  );

  test(
    'multiple Skills share one Agent root but one Skill cannot duplicate it',
    () async {
      await _insertSkillGraph(database);
      await _insertSkillGraph(
        database,
        skillId: _secondSkillId,
        lineageId: _secondLineageId,
        slotKey: 'reviewer-two',
      );
      final now = DateTime.now().toUtc().microsecondsSinceEpoch;
      Future<void> insertActivation(String id, String skillId) => database
          .into(database.activationLocations)
          .insert(
            ActivationLocationsCompanion.insert(
              id: id,
              managedSkillId: skillId,
              canonicalPath: '/tmp/agents/shared-skills',
              scope: 'global',
              mode: 'copy',
              createdAtMicros: now,
            ),
          );

      await insertActivation(_activationId, _skillId);
      await insertActivation(_secondActivationId, _secondSkillId);
      await expectLater(
        insertActivation(_thirdActivationId, _skillId),
        throwsA(anything),
      );

      expect(await database.activationLocations.select().get(), hasLength(2));
    },
  );

  test(
    'unregistering a Project Root preserves Activation provenance snapshots',
    () async {
      await _insertSkillGraph(database);
      final now = DateTime.now().toUtc().microsecondsSinceEpoch;
      await database
          .into(database.projectRoots)
          .insert(
            ProjectRootsCompanion.insert(
              id: 'project-root',
              canonicalPath: '/workspace/project',
              createdAtMicros: now,
              updatedAtMicros: now,
            ),
          );
      await database
          .into(database.activationLocations)
          .insert(
            ActivationLocationsCompanion.insert(
              id: _activationId,
              managedSkillId: _skillId,
              canonicalPath: '/workspace/project/.claude/skills/reviewer',
              scope: 'project',
              mode: 'copy',
              projectRootId: const Value('project-root'),
              projectRootPath: const Value('/workspace/project'),
              createdAtMicros: now,
            ),
          );

      await (database.delete(
        database.projectRoots,
      )..where((row) => row.id.equals('project-root'))).go();

      expect(await database.projectRoots.select().get(), isEmpty);
      final activation = await database.activationLocations
          .select()
          .getSingle();
      expect(activation.projectRootId, 'project-root');
      expect(activation.projectRootPath, '/workspace/project');
      expect(
        activation.canonicalPath,
        '/workspace/project/.claude/skills/reviewer',
      );

      final foreignKeys = await database
          .customSelect('PRAGMA foreign_key_list(activation_locations)')
          .get();
      expect(
        foreignKeys.where(
          (row) =>
              row.read<String>('from') == 'project_root_id' ||
              row.read<String>('table') == 'project_roots',
        ),
        isEmpty,
      );
    },
  );

  test('history pagination is stable for equal timestamps', () async {
    for (var index = 0; index < 5; index++) {
      final operationId = '123e4567-e89b-42d3-a456-42661417410$index';
      await database
          .into(database.operationRecords)
          .insert(
            OperationRecordsCompanion.insert(
              operationId: operationId,
              kind: 'refresh',
              status: 'succeeded',
              retainWithoutSubjects: const Value(true),
              startedAtMicros: index < 3 ? 10 : 9,
              completedAtMicros: 11,
            ),
          );
    }

    final first = await database.operationHistoryPage(limit: 2);
    final cursorRow = first.last;
    final second = await database.operationHistoryPage(
      before: OperationHistoryCursor(
        startedAtMicros: cursorRow.startedAtMicros,
        operationId: cursorRow.operationId,
      ),
      limit: 2,
    );

    expect(first, hasLength(2));
    expect(second, hasLength(2));
    expect(
      first
          .map((row) => row.operationId)
          .toSet()
          .intersection(second.map((row) => row.operationId).toSet()),
      isEmpty,
    );
  });

  test('history pagination rejects non-positive page sizes', () async {
    expect(
      () => database.operationHistoryPage(limit: 0),
      throwsA(
        isA<ArgumentError>()
            .having((error) => error.name, 'name', 'limit')
            .having((error) => error.invalidValue, 'invalidValue', 0),
      ),
    );
    expect(() => database.operationHistoryPage(limit: -1), throwsArgumentError);
  });

  test('stale revision diagnostics contain both compared revisions', () {
    const error = StaleControlPlaneRevision(expected: 3, actual: 5);

    expect(
      error.toString(),
      'StaleControlPlaneRevision(expected: 3, actual: 5)',
    );
  });
}

Future<Object?> _pragma(WorkspaceDatabase database, String name) async {
  final row = await database.customSelect('PRAGMA $name').getSingle();
  return row.data.values.single;
}

Future<void> _insertSkillGraph(
  WorkspaceDatabase database, {
  String skillId = _skillId,
  String lineageId = _lineageId,
  String slotKey = 'reviewer',
  bool includeIncomingRevision = false,
}) async {
  final now = DateTime.now().toUtc().microsecondsSinceEpoch;
  await database.transaction(() async {
    await database
        .into(database.managedSkills)
        .insert(
          ManagedSkillsCompanion.insert(
            id: skillId,
            slotKey: slotKey,
            declaredName: slotKey,
            displayName: 'Reviewer',
            description: 'Reviews Skills.',
            activeSourceLineageId: lineageId,
            createdAtMicros: now,
            updatedAtMicros: now,
          ),
        );
    await database
        .into(database.sourceLineages)
        .insert(
          SourceLineagesCompanion.insert(
            id: lineageId,
            managedSkillId: skillId,
            objectFormat: 'sha1',
            createdAtMicros: now,
          ),
        );
    await database
        .into(database.skillSources)
        .insert(
          SkillSourcesCompanion.insert(
            sourceLineageId: lineageId,
            kind: 'git',
            payloadSchemaVersion: currentSourcePayloadSchemaVersion,
            payloadJson: '{"locator":"https://example.com/repo.git"}',
          ),
        );
    await database
        .into(database.revisionMetadata)
        .insert(
          RevisionMetadataCompanion.insert(
            sourceLineageId: lineageId,
            objectId: _objectId,
            contentHash: _hash,
            fileCount: 1,
            byteSize: 64,
            declaredName: slotKey,
            validationState: 'valid',
            createdAtMicros: now,
          ),
        );
    if (includeIncomingRevision) {
      await database
          .into(database.revisionMetadata)
          .insert(
            RevisionMetadataCompanion.insert(
              sourceLineageId: lineageId,
              objectId: _incomingObjectId,
              contentHash:
                  'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
              fileCount: 1,
              byteSize: 65,
              declaredName: slotKey,
              validationState: 'valid',
              createdAtMicros: now,
            ),
          );
    }
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
}

Future<void> _insertEveryPerSkillProjection(WorkspaceDatabase database) async {
  final now = DateTime.now().toUtc().microsecondsSinceEpoch;
  await database
      .into(database.draftWorkspaces)
      .insert(
        DraftWorkspacesCompanion.insert(
          managedSkillId: _skillId,
          sourceLineageId: _lineageId,
          baseObjectId: _objectId,
          purpose: 'updateCandidateResolution',
          createdAtMicros: now,
          updatedAtMicros: now,
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
          createdAtMicros: now,
          updatedAtMicros: now,
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
  await database
      .into(database.activationLocations)
      .insert(
        ActivationLocationsCompanion.insert(
          id: _activationId,
          managedSkillId: _skillId,
          canonicalPath: '/tmp/activation/reviewer',
          scope: 'global',
          mode: 'copy',
          createdAtMicros: now,
        ),
      );
  await database
      .into(database.activationAgents)
      .insert(
        ActivationAgentsCompanion.insert(
          activationLocationId: _activationId,
          agentId: 'claude',
        ),
      );
  await database
      .into(database.skillUserData)
      .insert(
        SkillUserDataCompanion.insert(
          managedSkillId: _skillId,
          favorite: const Value(true),
          favoriteChangedAtMicros: Value(now),
          note: const Value('Important'),
          noteUpdatedAtMicros: Value(now),
        ),
      );
  await database
      .into(database.personalTags)
      .insert(
        PersonalTagsCompanion.insert(
          id: _tagId,
          normalizedKey: 'work',
          displayName: 'Work',
          createdAtMicros: now,
          updatedAtMicros: now,
        ),
      );
  await database
      .into(database.skillTagAssignments)
      .insert(
        SkillTagAssignmentsCompanion.insert(
          managedSkillId: _skillId,
          personalTagId: _tagId,
          createdAtMicros: now,
        ),
      );
  await database
      .into(database.operationRecords)
      .insert(
        OperationRecordsCompanion.insert(
          operationId: _operationId,
          kind: 'publishDraft',
          status: 'succeeded',
          startedAtMicros: now,
          completedAtMicros: now,
        ),
      );
  await database
      .into(database.operationSubjects)
      .insert(
        OperationSubjectsCompanion.insert(
          subjectId: _subjectId,
          operationId: _operationId,
          managedSkillId: _skillId,
          sourceLineageId: const Value(_lineageId),
          beforeObjectId: const Value(_objectId),
          afterObjectId: const Value(_incomingObjectId),
          beforeContentHash: const Value(_hash),
          afterContentHash: const Value(
            'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
          ),
          displayName: 'Reviewer',
        ),
      );
  await database
      .into(database.operationJournals)
      .insert(
        OperationJournalsCompanion.insert(
          operationId: _operationId,
          kind: 'remove',
          phase: 'committed',
          planSchemaVersion: 1,
          planJson: '{"recoveryReference":"opaque"}',
          operationGeneration: 1,
          committedRepositoryRevision: const Value(1),
          startedAtMicros: now,
          updatedAtMicros: now,
        ),
      );
  await database
      .into(database.operationJournalSteps)
      .insert(
        OperationJournalStepsCompanion.insert(
          operationId: _operationId,
          sequence: 0,
          stepId: 'remove-store',
          kind: 'retireStore',
          status: 'completed',
          recoveryReference: 'opaque-reference',
        ),
      );
}
