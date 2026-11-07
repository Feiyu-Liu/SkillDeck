import 'package:skills_workspace/src/application/operations/destructive_recovery_intent.dart';
import 'package:skills_workspace/src/application/operations/operation_models.dart';
import 'package:skills_workspace/src/application/revision_store/managed_skill_revision_access_gate.dart';
import 'package:skills_workspace/src/composition/destructive_recovery_maintenance.dart';
import 'package:skills_workspace/src/domain/cancellation.dart';
import 'package:skills_workspace/src/domain/identifiers.dart';
import 'package:skills_workspace/src/platform/operations/operation_recovery_bundle.dart';
import 'package:test/test.dart';

void main() {
  test('prepare drains readers and verify reopens revision access', () async {
    final gate = ManagedSkillRevisionAccessGate();
    final maintenance = WorkspaceDestructiveRecoveryMaintenance(
      accessGate: gate,
    );
    final currentReader = await gate.acquireRead(_skillId);
    final preparation = maintenance.prepare(
      _context,
      _intent,
      CancellationToken.none(),
    );
    var prepared = false;
    preparation.then((_) => prepared = true);
    await Future<void>.delayed(Duration.zero);
    expect(prepared, isFalse);

    await currentReader.release();
    await preparation;

    final laterReader = gate.acquireRead(_skillId);
    var laterAdmitted = false;
    laterReader.then((_) => laterAdmitted = true);
    await Future<void>.delayed(Duration.zero);
    expect(laterAdmitted, isFalse);

    await maintenance.verify(_context, _intent);
    final admitted = await laterReader;
    await admitted.release();
  });

  test('rollback releases exclusive revision access', () async {
    final gate = ManagedSkillRevisionAccessGate();
    final maintenance = WorkspaceDestructiveRecoveryMaintenance(
      accessGate: gate,
    );
    await maintenance.prepare(_context, _intent, CancellationToken.none());

    await maintenance.rollback(_context, _intent);

    final reader = await gate.acquireRead(_skillId);
    await reader.release();
  });

  test('cancelled preparation leaves the gate available', () async {
    final gate = ManagedSkillRevisionAccessGate();
    final maintenance = WorkspaceDestructiveRecoveryMaintenance(
      accessGate: gate,
    );
    final cancellation = CancellationSource();
    await cancellation.cancel();

    await expectLater(
      maintenance.prepare(_context, _intent, cancellation.token),
      throwsStateError,
    );

    final reader = await gate.acquireRead(_skillId);
    await reader.release();
  });
}

final _intent = RemovalRecoveryIntent(
  skills: [
    DestructiveSkillRecoveryIntent(
      managedSkillId: _skillId,
      slotKey: 'sample',
      sourceLineages: [RecoverySourceLineageIntent(sourceLineage: _lineage)],
      activationIds: const [],
      hasDraft: false,
      hasUpdateCandidateSession: false,
    ),
  ],
);
final _context = OperationRecoveryContext(
  operationId: OperationId('123e4567-e89b-42d3-a456-426614174020'),
  expectedRepositoryRevision: RepositoryRevision(0),
  committedRepositoryRevision: RepositoryRevision(1),
  destructive: true,
);
final _skillId = ManagedSkillId('123e4567-e89b-42d3-a456-426614174000');
final _lineage = SourceLineageReference('123e4567-e89b-42d3-8456-426614174001');
