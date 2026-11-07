import 'package:skills_workspace/skills_workspace.dart';
import 'package:test/test.dart';

void main() {
  const firstUuid = '123e4567-e89b-42d3-a456-426614174000';
  const secondUuid = '123e4567-e89b-42d3-b456-426614174001';

  test('opaque identifiers are value types but not interchangeable', () {
    final skillId = ManagedSkillId(firstUuid);
    final sameSkillId = ManagedSkillId(firstUuid);
    final operationId = OperationId(firstUuid);

    expect(skillId, sameSkillId);
    expect(skillId.hashCode, sameSkillId.hashCode);
    expect(skillId, isNot(equals(operationId)));
    expect(skillId.value, firstUuid);
  });

  test('opaque identifier constructors reject non-canonical UUIDv4 values', () {
    for (final invalid in [
      '',
      'not-an-id',
      '123E4567-E89B-42D3-A456-426614174000',
      '123e4567-e89b-12d3-a456-426614174000',
      '123e4567-e89b-42d3-7456-426614174000',
    ]) {
      expect(() => ManagedSkillId(invalid), throwsArgumentError);
      expect(() => OperationId(invalid), throwsArgumentError);
    }
  });

  test('RepositoryRevision is non-negative, monotonic, and comparable', () {
    final initial = RepositoryRevision.initial();
    final next = initial.next();

    expect(initial.value, 0);
    expect(next, RepositoryRevision(1));
    expect(initial.compareTo(next), lessThan(0));
    expect(() => RepositoryRevision(-1), throwsArgumentError);
  });

  test('OperationSubjectReference preserves both parts of its identity', () {
    final operationId = OperationId(firstUuid);
    final reference = OperationSubjectReference(
      operationId: operationId,
      subjectId: secondUuid,
    );

    expect(
      reference,
      OperationSubjectReference(
        operationId: OperationId(firstUuid),
        subjectId: secondUuid,
      ),
    );
    expect(reference.operationId, operationId);
    expect(reference.subjectId, secondUuid);
    expect(
      () => OperationSubjectReference(
        operationId: operationId,
        subjectId: 'invalid',
      ),
      throwsArgumentError,
    );
  });
}
