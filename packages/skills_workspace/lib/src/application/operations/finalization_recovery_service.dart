import 'operation_coordinator.dart';
import 'operation_models.dart';

/// Internal recovery seam used by the public finalization-resume command.
///
/// Implementations must keep Journal and writer-lock ownership inside the
/// Workspace application layer. Callers receive only an aggregate recovery
/// report and cannot address private recovery material directly.
abstract interface class WorkspaceFinalizationRecoveryPort {
  Future<OperationRecoveryReport> resumeFinalizationRecovery();
}

/// Reuses [OperationCoordinator.recover], which owns the cross-process Writer
/// Lock and durable Journal recovery. Concurrent callers coalesce onto one
/// in-flight attempt: repeated recovery scans cannot race each other or repeat
/// the same finalization work.
final class OperationCoordinatorFinalizationRecovery
    implements WorkspaceFinalizationRecoveryPort {
  OperationCoordinatorFinalizationRecovery({
    required OperationCoordinator operations,
  }) : _recover = operations.recover;

  /// Test-only construction seam for exercising in-flight coalescing without
  /// rebuilding a complete Journal fixture.
  OperationCoordinatorFinalizationRecovery.withRecovery({
    required Future<OperationRecoveryReport> Function() recover,
  }) : _recover = recover;

  final Future<OperationRecoveryReport> Function() _recover;
  Future<OperationRecoveryReport>? _inFlight;

  @override
  Future<OperationRecoveryReport> resumeFinalizationRecovery() {
    final inFlight = _inFlight;
    if (inFlight != null) return inFlight;

    final started = _recover();
    _inFlight = started;
    started.then<void>(
      (_) => _clearIfCurrent(started),
      onError: (Object error, StackTrace stackTrace) =>
          _clearIfCurrent(started),
    );
    return started;
  }

  void _clearIfCurrent(Future<OperationRecoveryReport> value) {
    if (identical(_inFlight, value)) _inFlight = null;
  }
}
