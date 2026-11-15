import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:skills_workspace/src/application/operations/operation_models.dart';
import 'package:skills_workspace/src/application/backup/control_plane_backup_models.dart';
import 'package:skills_workspace/src/domain/identifiers.dart';
import 'package:skills_workspace/src/infrastructure/database/drift_operation_control_plane.dart';
import 'package:skills_workspace/src/infrastructure/database/operation_plan_codec.dart';
import 'package:skills_workspace/src/infrastructure/database/workspace_database.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import 'generated/schema.dart';

void main() {
  late Directory temporary;
  setUp(
    () async => temporary = await Directory.systemTemp.createTemp(
      'workspace-identity-migration-',
    ),
  );
  tearDown(() async => temporary.delete(recursive: true));

  test(
    'real v3 rows and v4 Prepared Journal survive identity migration and rollback recovery',
    () async {
      final file = File('${temporary.path}/legacy.sqlite');
      final legacy = GeneratedHelper().databaseForVersion(
        NativeDatabase(file),
        3,
      );
      await legacy.customSelect('SELECT 1').getSingle();
      await legacy.close();
      final operationId = OperationId('123e4567-e89b-42d3-a456-426614174123');
      final envelope = PreparedOperationEnvelope(
        operationId: operationId,
        expectedRepositoryRevision: RepositoryRevision(7),
        committedRepositoryRevision: RepositoryRevision(8),
        operationGeneration: 8,
        preparationSteps: [
          PreparationOperationStep(
            stepId: 'legacy.prepare',
            recoveryReference: RecoveryReference(
              'or1:${operationId.value}:candidate',
            ),
            kind: PreparationStepKind.revisionCandidate,
          ),
        ],
        record: OperationRecordPlan(
          operationId: operationId,
          kind: 'setFavorite',
          subjects: [],
          retainWithoutSubjects: true,
        ),
      );
      final payload = const OperationPlanCodec().encodeDefinition(envelope);
      const skill = '123e4567-e89b-42d3-a456-426614174124';
      const lineage = '123e4567-e89b-42d3-a456-426614174125';
      final raw = sqlite3.open(file.path);
      try {
        expect(raw.userVersion, 3);
        raw.execute('BEGIN');
        raw.execute('INSERT INTO workspace_metadata VALUES (1, 7, 2, 1, 10)');
        raw.execute(
          'INSERT INTO managed_skills VALUES (?, ?, ?, ?, ?, ?, 1, 2)',
          [skill, 'fixture', 'fixture', 'Fixture', 'Kept description', lineage],
        );
        raw.execute('INSERT INTO source_lineages VALUES (?, ?, ?, 1)', [
          lineage,
          skill,
          'sha1',
        ]);
        raw.execute('INSERT INTO skill_sources VALUES (?, ?, 1, ?)', [
          lineage,
          'local',
          jsonEncode({'locator': temporary.path, 'skillPath': ''}),
        ]);
        raw.execute(
          'INSERT INTO revision_metadata VALUES (?, ?, ?, 1, 7, ?, ?, NULL, 1)',
          [lineage, 'a' * 40, 'b' * 64, 'fixture', 'valid'],
        );
        raw.execute(
          'INSERT INTO current_revision_selection VALUES (?, ?, ?, ?)',
          [skill, lineage, 'a' * 40, 'a' * 40],
        );
        raw.execute('INSERT INTO skill_user_data VALUES (?, 1, 2, ?, 3)', [
          skill,
          'preserved note',
        ]);
        raw.execute(
          'INSERT INTO operation_journals VALUES (?, ?, ?, 4, ?, 8, NULL, 1, 2)',
          [operationId.value, 'setFavorite', 'prepared', payload],
        );
        raw.execute(
          'INSERT INTO operation_journal_steps VALUES (?, 0, ?, ?, ?, ?)',
          [
            operationId.value,
            'legacy.prepare',
            'revisionCandidate',
            'planned',
            'or1:${operationId.value}:candidate',
          ],
        );
        raw.execute('COMMIT');
      } finally {
        raw.close();
      }
      final probeOwner = WorkspaceDatabase.forFile(
        File('${temporary.path}/unopened-owner.sqlite'),
      );
      final probe = await probeOwner.probeDatabase(
        file.path,
        integrityLevel: ControlPlaneIntegrityLevel.full,
      );
      expect(probe, isA<ControlPlaneHealthy>());
      expect((probe as ControlPlaneHealthy).identity.schemaVersion, 3);
      await probeOwner.close();
      final database = WorkspaceDatabase.forFile(file);
      final metadata = await database
          .select(database.workspaceMetadata)
          .getSingle();
      expect(metadata.repositoryRevision, 7);
      expect(metadata.destructionEpoch, 2);
      expect(metadata.workspaceId, matches(RegExp(r'^[0-9a-f-]{36}$')));
      expect(metadata.recoveryIncarnation, isNot(metadata.workspaceId));
      expect(
        (await database.select(database.skillUserData).getSingle()).note,
        'preserved note',
      );
      expect(
        (await database.select(database.managedSkills).getSingle()).displayName,
        'Fixture',
      );
      final plane = DriftOperationControlPlane(
        database: database,
        clock: () => 20,
      );
      final recovered = await plane.loadRecoverableOperations();
      expect(recovered.single.definition, isA<PreparedOperationEnvelope>());
      expect(
        const OperationPlanCodec().encodeDefinition(
          recovered.single.definition,
        ),
        payload,
      );
      await plane.completePreparedEnvelopeRollback(
        recovered.single.definition as PreparedOperationEnvelope,
        OperationAbortReason.cancelled,
      );
      await plane.deleteCompletedJournal(operationId);
      expect(await database.select(database.operationJournals).get(), isEmpty);
      expect(
        (await database.select(database.operationRecords).getSingle()).status,
        'cancelled',
      );
      expect(
        (await database.customSelect('PRAGMA foreign_key_check').get()),
        isEmpty,
      );
      final identity = (metadata.workspaceId, metadata.recoveryIncarnation);
      await database.close();
      final again = WorkspaceDatabase.forFile(file);
      final reopened = await again.select(again.workspaceMetadata).getSingle();
      expect((reopened.workspaceId, reopened.recoveryIncarnation), identity);
      await again.close();
      final downgraded = WorkspaceDatabase.forTesting(
        NativeDatabase(file),
        schemaVersionOverride: 3,
      );
      await expectLater(
        downgraded.customSelect('SELECT 1').getSingle(),
        throwsA(anything),
      );
      await downgraded.close();
      final verify = sqlite3.open(file.path);
      expect(verify.userVersion, 4);
      expect(
        verify.select('SELECT note FROM skill_user_data').single['note'],
        'preserved note',
      );
      verify.close();
    },
  );

  test(
    'a verified database copy retains workspaceId and changes only its recovery incarnation',
    () async {
      final file = File('${temporary.path}/primary.sqlite');
      final database = WorkspaceDatabase.forFile(file);
      final before = await database
          .select(database.workspaceMetadata)
          .getSingle();
      final staged = '${temporary.path}/restored.sqlite';
      await database.vacuumInto(staged);
      await database.markRestoredIncarnation(staged);
      final copy = WorkspaceDatabase.forFile(File(staged));
      final restored = await copy.select(copy.workspaceMetadata).getSingle();
      expect(restored.workspaceId, before.workspaceId);
      expect(restored.recoveryIncarnation, isNot(before.recoveryIncarnation));
      expect(restored.repositoryRevision, before.repositoryRevision);
      expect(restored.destructionEpoch, before.destructionEpoch);
      expect(
        (await database.select(database.workspaceMetadata).getSingle())
            .recoveryIncarnation,
        before.recoveryIncarnation,
      );
      await copy.close();
      await database.close();
    },
  );
}
