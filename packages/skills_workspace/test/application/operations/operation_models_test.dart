import 'package:skills_workspace/src/application/operations/operation_models.dart';
import 'package:skills_workspace/src/application/runtime/revision_engine_port.dart';
import 'package:skills_workspace/src/domain/identifiers.dart';
import 'package:test/test.dart';

void main() {
  group('OperationRecordPlan.withoutSubjects', () {
    test('combines selectors instead of removing either match', () {
      final fixture = _recordFixture();

      final retained = fixture.record.withoutSubjects(
        managedSkillId: fixture.skillA,
        sourceLineage: fixture.lineageOne,
      );

      expect(retained, isNotNull);
      expect(retained!.subjects, <OperationSubjectPlan>[
        fixture.skillCLineageTwo,
        fixture.skillBLineageOne,
      ]);
    });

    test('removes every subject for a selected managed Skill', () {
      final fixture = _recordFixture();

      final retained = fixture.record.withoutSubjects(
        managedSkillId: fixture.skillA,
      );

      expect(retained!.subjects, <OperationSubjectPlan>[
        fixture.skillCLineageTwo,
        fixture.skillBLineageOne,
      ]);
    });

    test('removes the header when its last subject is removed', () {
      final fixture = _recordFixture();
      final singleSubjectRecord = OperationRecordPlan(
        operationId: fixture.operationId,
        kind: 'single-subject',
        subjects: <OperationSubjectPlan>[fixture.skillALineageOne],
      );

      expect(
        singleSubjectRecord.withoutSubjects(managedSkillId: fixture.skillA),
        isNull,
      );
    });

    test('preserves an independently meaningful empty header', () {
      final fixture = _recordFixture();
      final record = OperationRecordPlan(
        operationId: fixture.operationId,
        kind: 'workspace-operation',
        subjects: <OperationSubjectPlan>[fixture.skillALineageOne],
        retainWithoutSubjects: true,
      );

      final retained = record.withoutSubjects(managedSkillId: fixture.skillA);

      expect(retained, isNotNull);
      expect(retained!.subjects, isEmpty);
      expect(retained.retainWithoutSubjects, isTrue);
    });

    test('rejects subjects owned by another operation', () {
      final fixture = _recordFixture();
      final otherOperationId = OperationId(
        '10000000-0000-4000-8000-000000000002',
      );

      expect(
        () => OperationRecordPlan(
          operationId: otherOperationId,
          kind: 'invalid-operation',
          subjects: <OperationSubjectPlan>[fixture.skillALineageOne],
        ),
        throwsArgumentError,
      );
    });

    test('rejects duplicate managed Skill subjects', () {
      final fixture = _recordFixture();
      final duplicateSkill = _subject(
        operationId: fixture.operationId,
        subjectSeed: 4,
        managedSkillId: fixture.skillA,
        sourceLineage: SourceLineageReference('lineage-other'),
      );

      expect(
        () => OperationRecordPlan(
          operationId: fixture.operationId,
          kind: 'invalid-operation',
          subjects: <OperationSubjectPlan>[
            fixture.skillALineageOne,
            duplicateSkill,
          ],
        ),
        throwsArgumentError,
      );
    });
  });

  group('RevisionSelectionChangePlan', () {
    final skillId = ManagedSkillId('20000000-0000-4000-8000-000000000001');
    final lineage = SourceLineageReference('lineage-1');
    final otherLineage = SourceLineageReference('lineage-2');
    final revision = RevisionAddress(
      sourceLineage: lineage,
      objectId: RevisionObjectId('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'),
    );
    final otherRevision = RevisionAddress(
      sourceLineage: otherLineage,
      objectId: RevisionObjectId('bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'),
    );

    test('allows an absent previous pair for initial install', () {
      expect(
        RevisionSelectionChangePlan(
          managedSkillId: skillId,
          previousUpstream: null,
          previousEffective: null,
          intendedUpstream: revision,
          intendedEffective: revision,
        ).intendedUpstream,
        revision,
      );
    });

    test('rejects a partial revision pair', () {
      expect(
        () => RevisionSelectionChangePlan(
          managedSkillId: skillId,
          previousUpstream: revision,
          previousEffective: null,
          intendedUpstream: revision,
          intendedEffective: revision,
        ),
        throwsArgumentError,
      );
    });

    test('rejects one pair spanning Source Lineages', () {
      expect(
        () => RevisionSelectionChangePlan(
          managedSkillId: skillId,
          previousUpstream: revision,
          previousEffective: otherRevision,
          intendedUpstream: revision,
          intendedEffective: revision,
        ),
        throwsArgumentError,
      );
    });
  });
}

_RecordFixture _recordFixture() {
  final operationId = OperationId('10000000-0000-4000-8000-000000000001');
  final skillA = ManagedSkillId('20000000-0000-4000-8000-000000000001');
  final skillB = ManagedSkillId('20000000-0000-4000-8000-000000000002');
  final skillC = ManagedSkillId('20000000-0000-4000-8000-000000000003');
  final lineageOne = SourceLineageReference('lineage-1');
  final lineageTwo = SourceLineageReference('lineage-2');
  final skillALineageOne = _subject(
    operationId: operationId,
    subjectSeed: 1,
    managedSkillId: skillA,
    sourceLineage: lineageOne,
  );
  final skillCLineageTwo = _subject(
    operationId: operationId,
    subjectSeed: 2,
    managedSkillId: skillC,
    sourceLineage: lineageTwo,
  );
  final skillBLineageOne = _subject(
    operationId: operationId,
    subjectSeed: 3,
    managedSkillId: skillB,
    sourceLineage: lineageOne,
  );
  return _RecordFixture(
    operationId: operationId,
    skillA: skillA,
    lineageOne: lineageOne,
    skillALineageOne: skillALineageOne,
    skillCLineageTwo: skillCLineageTwo,
    skillBLineageOne: skillBLineageOne,
    record: OperationRecordPlan(
      operationId: operationId,
      kind: 'multi-skill-update',
      subjects: <OperationSubjectPlan>[
        skillALineageOne,
        skillCLineageTwo,
        skillBLineageOne,
      ],
    ),
  );
}

OperationSubjectPlan _subject({
  required OperationId operationId,
  required int subjectSeed,
  required ManagedSkillId managedSkillId,
  required SourceLineageReference sourceLineage,
}) {
  final suffix = subjectSeed.toString().padLeft(12, '0');
  return OperationSubjectPlan(
    reference: OperationSubjectReference(
      operationId: operationId,
      subjectId: '30000000-0000-4000-8000-$suffix',
    ),
    managedSkillId: managedSkillId,
    displayName: 'Skill $subjectSeed',
    sourceLineage: sourceLineage,
  );
}

final class _RecordFixture {
  const _RecordFixture({
    required this.operationId,
    required this.skillA,
    required this.lineageOne,
    required this.skillALineageOne,
    required this.skillCLineageTwo,
    required this.skillBLineageOne,
    required this.record,
  });

  final OperationId operationId;
  final ManagedSkillId skillA;
  final SourceLineageReference lineageOne;
  final OperationSubjectPlan skillALineageOne;
  final OperationSubjectPlan skillCLineageTwo;
  final OperationSubjectPlan skillBLineageOne;
  final OperationRecordPlan record;
}
