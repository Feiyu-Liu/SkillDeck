import '../application/operations/destructive_recovery_intent.dart';
import '../application/revision_store/managed_skill_revision_access_gate.dart';
import '../domain/cancellation.dart';
import '../domain/identifiers.dart';
import '../platform/operations/filesystem_operation_recovery.dart';
import '../platform/operations/operation_recovery_bundle.dart';

/// Serializes destructive canonical Store replacement with in-process readers.
final class WorkspaceDestructiveRecoveryMaintenance
    implements OperationRecoveryDestructiveMaintenancePort {
  WorkspaceDestructiveRecoveryMaintenance({
    required ManagedSkillRevisionAccessGate accessGate,
  }) : _accessGate = accessGate;

  final ManagedSkillRevisionAccessGate _accessGate;
  final Map<OperationId, List<ManagedSkillRevisionAccessPermit>> _permits = {};

  @override
  Future<void> prepare(
    OperationRecoveryContext context,
    DestructiveOperationRecoveryIntent intent,
    CancellationToken cancellationToken,
  ) async {
    if (cancellationToken.isCancelled) {
      throw StateError('Destructive preparation was cancelled.');
    }
    await _acquire(context.operationId, intent, cancellationToken);
  }

  @override
  Future<void> verify(
    OperationRecoveryContext context,
    DestructiveOperationRecoveryIntent intent,
  ) => _release(context.operationId);

  @override
  Future<void> rollback(
    OperationRecoveryContext context,
    DestructiveOperationRecoveryIntent intent,
  ) => _release(context.operationId);

  @override
  Future<void> rollForward(
    OperationRecoveryContext context,
    DestructiveOperationRecoveryIntent intent,
  ) => _acquire(context.operationId, intent, CancellationToken.none());

  Future<void> _acquire(
    OperationId operationId,
    DestructiveOperationRecoveryIntent intent,
    CancellationToken cancellationToken,
  ) async {
    if (_permits.containsKey(operationId)) return;
    final skillIds = intent.skills.map((skill) => skill.managedSkillId).toList()
      ..sort((left, right) => left.value.compareTo(right.value));
    final acquired = <ManagedSkillRevisionAccessPermit>[];
    try {
      for (final skillId in skillIds) {
        acquired.add(
          await _accessGate.acquireExclusive(
            skillId,
            cancellationToken: cancellationToken,
          ),
        );
      }
      _permits[operationId] = acquired;
    } catch (_) {
      await _releasePermits(acquired);
      rethrow;
    }
  }

  Future<void> _release(OperationId operationId) async {
    final permits = _permits.remove(operationId);
    if (permits == null) return;
    await _releasePermits(permits);
  }
}

Future<void> _releasePermits(
  List<ManagedSkillRevisionAccessPermit> permits,
) async {
  for (final permit in permits.reversed) {
    await permit.release();
  }
}
