import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:skills_workspace/src/domain/identifiers.dart';
import 'package:skills_workspace/src/domain/public_models.dart';
import 'package:skills_workspace/src/infrastructure/database/workspace_database.dart';
import 'package:skills_workspace/src/infrastructure/database/workspace_history_reader.dart';
import 'package:test/test.dart';

const _firstSkillId = '123e4567-e89b-42d3-a456-426614174000';
const _secondSkillId = '123e4567-e89b-42d3-b456-426614174001';
const _firstLineageId = '123e4567-e89b-42d3-8456-426614174002';
const _secondLineageId = '123e4567-e89b-42d3-9456-426614174003';
const _objectId = '0123456789012345678901234567890123456789';
const _hashA =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _hashB =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

void main() {
  late Directory temporaryDirectory;
  late WorkspaceDatabase database;
  late WorkspaceHistoryReader reader;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'skills-workspace-history-reader-',
    );
    database = WorkspaceDatabase.forFile(
      File('${temporaryDirectory.path}/workspace.sqlite'),
    );
    await database.workspaceMetadata.select().getSingle();
    await _insertSkillGraph(
      database,
      skillId: _firstSkillId,
      lineageId: _firstLineageId,
      slotKey: 'first',
    );
    await _insertSkillGraph(
      database,
      skillId: _secondSkillId,
      lineageId: _secondLineageId,
      slotKey: 'second',
    );
    reader = WorkspaceHistoryReader(database);
  });

  tearDown(() async {
    await database.close();
    await temporaryDirectory.delete(recursive: true);
  });

  test('paginates operation history deterministically', () async {
    for (var index = 0; index < 4; index++) {
      await _insertRecord(
        database,
        suffix: index,
        kind: WorkspaceOperationKind.refresh,
        startedAt: index < 3 ? 100 : 90,
        retainWithoutSubjects: true,
      );
    }

    final first = await reader.readOperationHistory(limit: 2);
    final second = await reader.readOperationHistory(
      cursor: first.nextCursor,
      limit: 2,
    );

    expect(first.entries, hasLength(2));
    expect(first.nextCursor, isNotNull);
    expect(second.entries, hasLength(2));
    expect(second.nextCursor, isNull);
    expect(
      first.entries
          .map((entry) => entry.operationId)
          .toSet()
          .intersection(
            second.entries.map((entry) => entry.operationId).toSet(),
          ),
      isEmpty,
    );
  });

  test('filters operation history by subject and maps subjects', () async {
    await _insertRecord(
      database,
      suffix: 0,
      kind: WorkspaceOperationKind.install,
      startedAt: 100,
      subject: _SubjectSeed(
        skillId: _firstSkillId,
        lineageId: _firstLineageId,
        displayName: 'First',
        afterHash: _hashA,
      ),
    );
    await _insertRecord(
      database,
      suffix: 1,
      kind: WorkspaceOperationKind.install,
      startedAt: 101,
      subject: _SubjectSeed(
        skillId: _secondSkillId,
        lineageId: _secondLineageId,
        displayName: 'Second',
        afterHash: _hashB,
      ),
    );
    await _insertRecord(
      database,
      suffix: 2,
      kind: WorkspaceOperationKind.refresh,
      startedAt: 102,
      retainWithoutSubjects: true,
    );

    final page = await reader.readOperationHistory(
      managedSkillId: ManagedSkillId(_firstSkillId),
      limit: 10,
    );

    expect(page.entries, hasLength(1));
    expect(page.entries.single.kind, WorkspaceOperationKind.install);
    expect(page.entries.single.status, OperationTerminalStatus.succeeded);
    expect(page.entries.single.subjects.single.displayName, 'First');
    expect(page.entries.single.subjects.single.afterContentHash, _hashA);
  });

  test('published history includes only durable after revisions', () async {
    await _insertRecord(
      database,
      suffix: 0,
      kind: WorkspaceOperationKind.install,
      startedAt: 100,
      completedAt: 110,
      subject: _SubjectSeed(
        skillId: _firstSkillId,
        lineageId: _firstLineageId,
        displayName: 'First',
        afterHash: _hashA,
      ),
    );
    await _insertRecord(
      database,
      suffix: 1,
      kind: WorkspaceOperationKind.setFavorite,
      startedAt: 111,
      completedAt: 112,
      subject: const _SubjectSeed(skillId: _firstSkillId, displayName: 'First'),
    );
    await _insertRecord(
      database,
      suffix: 2,
      kind: WorkspaceOperationKind.publishDraft,
      startedAt: 120,
      completedAt: 130,
      subject: _SubjectSeed(
        skillId: _firstSkillId,
        lineageId: _firstLineageId,
        displayName: 'First',
        afterHash: _hashB,
      ),
    );

    final first = await reader.readPublishedHistory(
      managedSkillId: ManagedSkillId(_firstSkillId),
      limit: 1,
    );
    final second = await reader.readPublishedHistory(
      managedSkillId: ManagedSkillId(_firstSkillId),
      cursor: first.nextCursor,
      limit: 1,
    );

    expect(first.revisions.single.kind, WorkspaceOperationKind.publishDraft);
    expect(first.revisions.single.contentHash, _hashB);
    expect(second.revisions.single.kind, WorkspaceOperationKind.install);
    expect(second.revisions.single.contentHash, _hashA);
    expect(second.nextCursor, isNull);
  });

  test('cursor kinds are isolated and malformed cursors fail closed', () async {
    await _insertRecord(
      database,
      suffix: 0,
      kind: WorkspaceOperationKind.install,
      startedAt: 100,
      subject: _SubjectSeed(
        skillId: _firstSkillId,
        lineageId: _firstLineageId,
        displayName: 'First',
        afterHash: _hashA,
      ),
    );
    await _insertRecord(
      database,
      suffix: 1,
      kind: WorkspaceOperationKind.install,
      startedAt: 90,
      subject: _SubjectSeed(
        skillId: _firstSkillId,
        lineageId: _firstLineageId,
        displayName: 'First',
        afterHash: _hashA,
      ),
    );
    final operations = await reader.readOperationHistory(limit: 1);

    expect(
      () => reader.readPublishedHistory(
        managedSkillId: ManagedSkillId(_firstSkillId),
        cursor: operations.nextCursor,
        limit: 1,
      ),
      throwsArgumentError,
    );
    expect(
      () => reader.readOperationHistory(cursor: 'not-a-cursor', limit: 1),
      throwsArgumentError,
    );
  });
}

Future<void> _insertSkillGraph(
  WorkspaceDatabase database, {
  required String skillId,
  required String lineageId,
  required String slotKey,
}) async {
  await database.transaction(() async {
    await database
        .into(database.managedSkills)
        .insert(
          ManagedSkillsCompanion.insert(
            id: skillId,
            slotKey: slotKey,
            declaredName: slotKey,
            displayName: slotKey,
            description: '$slotKey description',
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
            payloadJson: '{"locator":"/tmp/$slotKey"}',
          ),
        );
    await database
        .into(database.revisionMetadata)
        .insert(
          RevisionMetadataCompanion.insert(
            sourceLineageId: lineageId,
            objectId: _objectId,
            contentHash: _hashA,
            fileCount: 1,
            byteSize: 1,
            declaredName: slotKey,
            validationState: 'valid',
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
}

Future<void> _insertRecord(
  WorkspaceDatabase database, {
  required int suffix,
  required WorkspaceOperationKind kind,
  required int startedAt,
  int? completedAt,
  bool retainWithoutSubjects = false,
  _SubjectSeed? subject,
}) async {
  final operationId = '123e4567-e89b-42d3-a456-42661417410$suffix';
  await database
      .into(database.operationRecords)
      .insert(
        OperationRecordsCompanion.insert(
          operationId: operationId,
          kind: kind.name,
          status: 'succeeded',
          retainWithoutSubjects: Value(retainWithoutSubjects),
          startedAtMicros: startedAt,
          completedAtMicros: completedAt ?? startedAt,
        ),
      );
  if (subject == null) return;
  await database
      .into(database.operationSubjects)
      .insert(
        OperationSubjectsCompanion.insert(
          subjectId: '123e4567-e89b-42d3-b456-42661417420$suffix',
          operationId: operationId,
          managedSkillId: subject.skillId,
          sourceLineageId: Value(subject.lineageId),
          afterObjectId: Value(subject.lineageId == null ? null : _objectId),
          afterContentHash: Value(subject.afterHash),
          displayName: subject.displayName,
        ),
      );
}

final class _SubjectSeed {
  const _SubjectSeed({
    required this.skillId,
    required this.displayName,
    this.lineageId,
    this.afterHash,
  });

  final String skillId;
  final String displayName;
  final String? lineageId;
  final String? afterHash;
}
