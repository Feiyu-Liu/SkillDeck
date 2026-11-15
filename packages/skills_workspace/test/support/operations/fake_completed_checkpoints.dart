import 'package:skills_workspace/src/application/operations/operation_models.dart';
import 'package:skills_workspace/src/application/ports/operation_ports.dart';

/// Explicit fixture for tests that intentionally do not model real backups.
final class FakeCompletedCheckpoints
    implements OperationCompletedCheckpointPort {
  const FakeCompletedCheckpoints({this.onCheckpoint});
  final void Function(String phase)? onCheckpoint;
  @override
  Future<void> terminalCheckpoint(OperationPlan plan) async =>
      onCheckpoint?.call('terminal');
  @override
  Future<void> cleanCheckpoint(OperationPlan plan) async =>
      onCheckpoint?.call('clean');
}
