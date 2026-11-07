import 'package:skills_workspace/src/application/revision_store/managed_skill_revision_access_gate.dart';
import 'package:skills_workspace/src/domain/cancellation.dart';
import 'package:skills_workspace/src/domain/identifiers.dart';
import 'package:test/test.dart';

void main() {
  final skill = ManagedSkillId('00000000-0000-4000-8000-000000000001');

  test('admits concurrent readers', () async {
    final gate = ManagedSkillRevisionAccessGate();

    final first = await gate.acquireRead(skill);
    final second = await gate.acquireRead(skill);

    await first.release();
    await second.release();
  });

  test('writer drains readers and blocks later readers', () async {
    final gate = ManagedSkillRevisionAccessGate();
    final first = await gate.acquireRead(skill);
    final writerFuture = gate.acquireExclusive(skill);
    final laterReaderFuture = gate.acquireRead(skill);

    var writerCompleted = false;
    var laterReaderCompleted = false;
    writerFuture.then((_) => writerCompleted = true);
    laterReaderFuture.then((_) => laterReaderCompleted = true);
    await Future<void>.delayed(Duration.zero);
    expect(writerCompleted, isFalse);
    expect(laterReaderCompleted, isFalse);

    await first.release();
    final writer = await writerFuture;
    expect(writerCompleted, isTrue);
    expect(laterReaderCompleted, isFalse);

    await writer.release();
    final laterReader = await laterReaderFuture;
    await laterReader.release();
  });

  test('cancels a queued request without blocking the gate', () async {
    final gate = ManagedSkillRevisionAccessGate();
    final reader = await gate.acquireRead(skill);
    final cancellation = CancellationSource();
    final writer = gate.acquireExclusive(
      skill,
      cancellationToken: cancellation.token,
    );

    await cancellation.cancel();
    await expectLater(
      writer,
      throwsA(isA<ManagedSkillRevisionAccessCancelled>()),
    );
    await reader.release();

    final next = await gate.acquireExclusive(skill);
    await next.release();
  });

  test('release is idempotent', () async {
    final gate = ManagedSkillRevisionAccessGate();
    final permit = await gate.acquireExclusive(skill);

    await permit.release();
    await permit.release();

    final reader = await gate.acquireRead(skill);
    await reader.release();
  });
}
