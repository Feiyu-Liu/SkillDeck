import 'dart:async';

import '../../domain/identifiers.dart';
import '../ports/workspace_lifecycle_ports.dart';

/// One admitted request tracked until its terminal result is published.
final class WorkspaceRequestAdmission {
  WorkspaceRequestAdmission._({
    required this.operationId,
    required Future<void> Function() cancelBeforeCommit,
    required void Function(WorkspaceRequestAdmission) onFinished,
  }) : _cancelBeforeCommit = cancelBeforeCommit,
       _onFinished = onFinished;

  final OperationId operationId;
  final Future<void> Function() _cancelBeforeCommit;
  final void Function(WorkspaceRequestAdmission) _onFinished;
  final Completer<void> _settled = Completer<void>();
  bool _businessCommitted = false;
  bool _finished = false;
  Future<void>? _cancellation;

  bool get businessCommitted => _businessCommitted;
  Future<void> get settled => _settled.future;

  /// Freezes cancellation at the durable Business Commit Point.
  void markBusinessCommitted() {
    if (_finished) return;
    _businessCommitted = true;
  }

  Future<void> cancelIfPreCommit() {
    if (_businessCommitted || _finished) return Future<void>.value();
    return _cancellation ??= _cancelBeforeCommit();
  }

  void finish() {
    if (_finished) return;
    _finished = true;
    _onFinished(this);
    _settled.complete();
  }
}

/// Serializes request admission and commit-aware shutdown draining.
final class WorkspaceRequestGate implements WorkspaceRequestGatePort {
  final Map<OperationId, WorkspaceRequestAdmission> _active = {};
  bool _accepting = false;
  bool _closed = false;

  bool get isAccepting => _accepting && !_closed;
  int get activeRequestCount => _active.length;

  WorkspaceRequestAdmission? admit({
    required OperationId operationId,
    required Future<void> Function() cancelBeforeCommit,
  }) {
    if (!isAccepting) return null;
    if (_active.containsKey(operationId)) {
      throw StateError('An Operation ID cannot be admitted twice.');
    }
    late final WorkspaceRequestAdmission admission;
    admission = WorkspaceRequestAdmission._(
      operationId: operationId,
      cancelBeforeCommit: cancelBeforeCommit,
      onFinished: (finished) {
        if (identical(_active[finished.operationId], finished)) {
          _active.remove(finished.operationId);
        }
      },
    );
    _active[operationId] = admission;
    return admission;
  }

  @override
  Future<void> openForRequests() async {
    if (_closed) throw StateError('The request gate has been closed.');
    _accepting = true;
  }

  @override
  Future<void> stopAccepting() async {
    _accepting = false;
  }

  @override
  Future<void> settleInFlightByCommitState() async {
    _accepting = false;
    final active = _active.values.toList(growable: false);
    await Future.wait<void>([
      for (final request in active) request.cancelIfPreCommit(),
    ]);
    await Future.wait<void>([for (final request in active) request.settled]);
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _accepting = false;
    if (_active.isNotEmpty) {
      throw StateError('In-flight requests must settle before gate close.');
    }
    _closed = true;
  }
}
